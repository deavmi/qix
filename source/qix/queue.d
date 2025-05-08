module qix.queue;

public alias QueueKey = size_t;

import core.sync.mutex : Mutex;
import core.sync.condition : Condition;
import std.datetime : Duration;

import gogga.mixins;

public template Queue(Item)
{
	public struct Queue
	{
		private QueueKey _id;

		private Mutex _l;
		private Condition _c;
		import std.container.slist : SList;
		import std.range : walkLength;
		private SList!(Item) _q;
		// todo: list here
		// todo: filter delegate to use on reception

		package this(QueueKey id)
		{
			this._id = id;
			this._l = new Mutex();
			this._c = new Condition(this._l);
			// show();
		}

		private void show()
		{
			DEBUG("this._l", cast(Object*)this._l);
			DEBUG("this._c", cast(Object*)this._c);
			DEBUG("this", &this);
		}

		public QueueKey id()
		{
			return this._id;
		}

		public bool receive(Item i)
		{
			// lock, apply filter delegate (if any), insert (if so), unlock
			this._l.lock();

			scope(exit)
			{
				this._l.unlock();
			}

			// todo: filter here (Document: API for filters hold lock?)
			this._q.insertAfter(this._q[], i); // todo: placement in queue?
			DEBUG("calling notify()...");
			this._c.notify(); // wake up one waiter

			show();

			DEBUG("post-notify");
			
			return true;
		}

		public Item wait()
		{
			return wait(Duration.zero());
		}

		public Item wait(Duration timeout)
		{
			show();
			
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
				return pop();
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
					// todo: throw exception here
					throw new Exception("Timeout after waiting"); // todo: log time taken
				}
			}
			
			// pop single item off
			return pop();
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

		// items in queue
		public size_t size()
		{
			this._l.lock();
			
			scope(exit)
			{
				this._l.unlock();
			}

			DEBUG("dd: ", walkLength(this._q[]));
			return walkLength(this._q[]);
		}

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

unittest
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

	Thread.sleep(dur!("seconds")(5));
}
