/** 
 * Definitions for queues
 *
 * Authors: Tristan Brice Velloza Kildaire (deavmi)
 */
module qix.queue;

/**
 * The type used to represent
 * a queue id
 */
public alias QueueKey = size_t;

import core.sync.mutex : Mutex;
import core.sync.condition : Condition;
import std.datetime : Duration;
import qix.exceptions;
import niknaks.functional : Result, ok, error;

import gogga.mixins;

/** 
 * Admittance policy
 *
 * A delegate that takes in an `Item`
 * and returns `true` if it should be
 * admitted to the queue, `false`
 * otherwise
 */
public alias AdmitPolicy(Item) = bool delegate(Item);

/** 
 * Timeout exception thrown when
 * a time-based wait times-out
 */
public final class TimeoutException : QixException
{
	private this()
	{
		super("Timeout after waiting");
	}
}

/** 
 * Queue type
 */
public template Queue(Item)
{
	private alias AP = AdmitPolicy!(Item);

	/** 
	 * Queue type
	 */
	public struct Queue
	{
		private QueueKey _id;

		private Mutex _l;
		private Condition _c;
		import std.container.slist : SList;
		import std.range : walkLength;
		private SList!(Item) _q;
		// todo: list here
		private AP _ap; // admit policy

		/** 
		 * Constructs a new queue with
		 * the given id and the admittance
		 * policy
		 *
		 * Params:
		 *   id = the id
		 *   ap = admittance policy
		 */
		package this(QueueKey id, AP ap) @safe
		{
			this._id = id;
			this._l = new Mutex();
			this._c = new Condition(this._l);
			this._ap = ap;
		}

		/** 
		 * Constructs a new queue with
		 * the given id
		 *
		 * Params:
		 *   id = the id
		 */
		package this(QueueKey id) @safe
		{
			this(id, null);
		}

		/** 
		 * Returns this queue's id
		 *
		 * Returns: the id
		 */
		public QueueKey id() @safe
		{
			return this._id;
		}

		private bool wouldAdmit(Item i)
		{
			// if no policy => true
			// else, apply policy
			bool s = this._ap is null ? true : this._ap(i);
			DEBUG("Admit policy returned: ", s);
			return s;
		}

		/** 
		 * Places an item into this queue and
		 * wakes up one of the waiter(s)
		 *
		 * The item is only enqueued if
		 * there is an admittance policy
		 * associated with this queue, and
		 * if so, if it evaluates to `true`.
		 *
		 * Params:
		 *   i = the item to attempt to enqueue
		 * Returns: `true` if enqueued, `false`
		 * otherwise
		 */
		public bool receive(Item i)
		{
			// lock, apply filter delegate (if any), insert (if so), unlock
			this._l.lock();

			scope(exit)
			{
				this._l.unlock();
			}

			if(!wouldAdmit(i))
			{
				DEBUG("Admit policy denied: '", i, "'");
				return false;
			}

			// todo: filter here (Document: API for filters hold lock?)
			this._q.insertAfter(this._q[], i); // todo: placement in queue?
			DEBUG("calling notify()...");
			this._c.notify(); // wake up one waiter

			DEBUG("post-notify");
			
			return true;
		}

		/** 
		 * Blocks until an item is available
		 * for dequeuing.
		 *
		 * This is akin to calling `wait(Duration)`
		 * with `Duration.zero`.
		 *
		 * Returns: the item
		 */
		public Item wait()
		{
			auto res = wait(Duration.zero());
			//sanity: only way an error is if timed out
			// but that should not be possible with
			// a timeout of 0
			assert(res.is_okay()); 
			return res.ok();
		}

		/** 
		 * Blocks up until the timeout for an
		 * item to become available for dequeuing.
		 *
		 * However, if the timeout is reached
		 * then an exception is returned.
		 *
		 * Params:
		 *   timeout = the timeout
		 * 
		 * Returns: a `Result` containing the
		 * the dequeued item or a `QixException`
		 * if the timeout was exceeded
		 */
		public Result!(Item, QixException) wait(Duration timeout)
		{
			this._l.lock();

			scope(exit)
			{
				this._l.unlock();
			}

			// check if item already present
			// then there is no need to wait
			DEBUG("calling size()");
			bool early_return = size() > 0;
			if(early_return)
			{
				DEBUG("early return");
				return ok!(Item, QixException)(pop());
			}

			// then no timeout
			if(timeout == Duration.zero)
			{
				DEBUG("wait()...");
				this._c.wait();
				DEBUG("wait()... [unblock]");
			}
			// handle timeouts
			else
			{
				DEBUG("wait(Duration)...");
				bool in_time = this._c.wait(timeout); // true if `notify()`'d before timeout
				DEBUG("wait(Duration)... [unblock]");
				DEBUG("timed out?: ", !in_time);

				if(!in_time)
				{
					return error!(QixException, Item)(new TimeoutException()); // todo: log time taken
				}
			}
			
			// pop single item off
			return ok!(Item, QixException)(pop());
		}

		// mt: assumes lock held
		private Item pop()
		{
			assert(size() > 0);

			import std.range;
			auto i = this._q.front(); // store
			this._q.removeFront(); // remove 

			DEBUG("popped item: ", i);
			return i;
		}

		/** 
		 * Returns the number of items
		 * in the queue
		 *
		 * Returns: the count
		 */
		public size_t size() // TODO: Make safe justd ebug that is bad
		{
			this._l.lock();
			
			scope(exit)
			{
				this._l.unlock();
			}

			DEBUG("dd: ", walkLength(this._q[]));
			return walkLength(this._q[]);
		}

		/** 
		 * Returns a string representation
		 * of this queue
		 *
		 * Returns: a string
		 */
		public string toString()
		{
			import std.string : format;
			return format
			(
				"Queue (qid: %d)",
				this._id	
			);
		}
	}
}

private version(unittest)
{
	import core.thread : Thread, dur;
}

private version(unittest)
{
	// custom item type
	class Message
	{
		private string _m;
		this(string m)
		{
			this._m = m;
		}
	
		public auto m()
		{
			return this._m;
		}
	}
}

unittest
{
	// create a single queue
	Queue!(Message) q = Queue!(Message)(1);

	// now make a thread that awaits reception
	// of message
	class Waiter : Thread
	{
		private Queue!(Message)* _q; // queue to wait on
		private Message _m; // (eventually) dequeued message
		// todo: make above volatile
		
		
		this(Queue!(Message)* q)
		{
			super(&run);
			this._q = q;
		}

		private void run()
		{
			DEBUG("waiter about to call wait()...");
			Message i = this._q.wait();
			this._m = i;
		}

		public Message m()
		{
			return this._m;
		}
	}
	Waiter wt = new Waiter(&q);
	wt.start();

	// todo: do version with sleep here and version without

	// Push a single message in
	Message m = new Message("Hey there");
	q.receive(m);

	// wait for thread to end and then grab the internal
	// value for comparison
	wt.join();
	DEBUG("Expected: ", m);
	DEBUG("Thread got: ", wt.m());
	assert(m == wt.m());

	// wait with timeout and knowing nothing will
	// be enqueued
	auto res = q.wait(dur!("seconds")(1));
	assert(res.is_error());
	assert(cast(TimeoutException)res.error());
}

// test admit policy
unittest
{
	// admit policy that accepts
	bool accept(Message m) { return true; }
	AdmitPolicy!(Message) ap_a = &accept;
	
	// create a single queue with it
	Queue!(Message) q1 = Queue!(Message)(1, ap_a);

	// should accept
	assert(q1.receive(new Message("Hi")));

	// admit policy that rejects
	bool reject(Message m) { return false; }
	AdmitPolicy!(Message) ap_r = &reject;
	
	// create a single queue with it
	Queue!(Message) q2 = Queue!(Message)(1, ap_r);

	// should reject
	assert(!q2.receive(new Message("Hi")));
}
