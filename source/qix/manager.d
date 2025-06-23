/** 
 * Queue management
 *
 * Authors: Tristan Brice Velloza Kildaire (deavmi)
 */
module qix.manager;

import qix.queue;
import niknaks.functional : Result, ok, error;
import std.string : format;
import gogga.mixins;

/** 
 * Default max iterations when
 * trying to find an unused queue
 * id
 */
private enum NEWQUEUE_MAX_ITER = 1000;

import qix.exceptions;

/** 
 * An exception that occurs during
 * usage of the `Manager`
 */
public final class ManagerException : QixException
{
	private this(string m)
	{
		super(m);
	}
}

/** 
 * A queue manager
 */
public template Manager(Item)
{
	/** 
	 * A queue manager
	 */
	public class Manager
	{
		import core.sync.mutex : Mutex;

		private alias QueueType = Queue!(Item);
		
		private QueueType[QueueKey] _q;
		private Mutex _ql; // todo: readers-writers lock

		private size_t _mi;

		/** 
		 * Construct a new queue manager
		 *
		 * Params:
		 *   maxIter = maximum number of
		 * iterations allowed when searching
		 * for a free queue id
		 */
		this(size_t maxIter)
		{
			this._ql = new Mutex();
			this._mi = maxIter;
		}

		/** 
		 * Constructs a new queue manager
		 */
		this()
		{
			this(NEWQUEUE_MAX_ITER);
		}

		/** 
		 * Finds an unused queue id and then
		 * instantiates a queue with that id
		 *
		 * Returns: a `Result` that contains
		 * a pointer to the queue if a free
		 * id was found, otherwise `false`
		 * if no free id could be found or
		 * we reached the maximum number
		 * of allowed iterations for searching
		 */
		public Result!(QueueType*, string) newQueue()
		{
			this._ql.lock();

			scope(exit)
			{
				this._ql.unlock();
			}

			// find a free queue id with the
			// random startergy
			Result!(QueueKey, string) qid_res = newQueue_randStrat();
			DEBUG("qid_res: ", qid_res);

			if(qid_res.is_error())
			{
				return error!(string, QueueType*)(qid_res.error());
			}

			// create new queue and insert it
			QueueKey qid = qid_res.ok();
			this._q[qid] = QueueType(qid);
			QueueType* q = qid in this._q;
			DEBUG("stored new queue: ", *q);

			return ok!(QueueType*, string)(q);
		}

		// uses a random dice roll as a startergy
		// for finding potentially free qids
		//
		// mt: assumes caller holds lock `this._ql`
		private Result!(QueueKey, string) newQueue_randStrat()
		{
			import qix.utils : rand;

			size_t c = 0; // iterations
			QueueKey new_qid;
			bool succ = false;
			for(c = 0; c < NEWQUEUE_MAX_ITER; c++)
			{
				// try find free qid
				new_qid = rand();
				if((new_qid in this._q) is null)
				{
					succ = true;
					break;
				}
			}
			DEBUG("iterations: ", c);

			// ran out of iterations before we
			// could fine free qid
			if(!succ)
			{
				return error!(string, QueueKey)
				(
					format
					(
						"Reached NEWQUEUE_MAX_ITER of %d before finding free queue id",
						NEWQUEUE_MAX_ITER
					)
				);
			}
			// found a free qid
			else
			{
				return ok!(QueueKey, string)(new_qid);
			}
		}

		/** 
		 * Removes the provided queue from the manager
		 *
		 * Params:
		 *   queue = a pointer to the queue
		 * Returns: `true` if the queue existed, `false`
		 * if not or if `null` was provided
		 */
		public bool removeQueue(QueueType* queue)
		{
			return queue is null ? false : removeQueue(queue.id());
		}

		/** 
		 * Removes the queue by the provided id
		 * from the manager
		 *
		 * Params:
		 *   key = the queue's id
		 * Returns: `true` if the queue existed, `false`
		 * otherwise
		 */
		public bool removeQueue(QueueKey key)
		{
			this._ql.lock();

			scope(exit)
			{
				this._ql.unlock();
			}

			QueueType* f = key in this._q;

			if(f is null)
			{
				return false;
			}

			this._q.remove(key);
			return true;
		}

		private QueueType* getQueue0(QueueKey id)
		{
			this._ql.lock();

			scope(exit)
			{
				this._ql.unlock();
			}

			return id in this._q;
		}

		private Result!(QueueType*, QixException) getQueue(QueueKey id)
		{
			auto q = getQueue0(id);
			if(q is null)
			{
				return error!(QixException, QueueType*)
				(
					new ManagerException
					(
						format
						(
							"Could not find a queue with id %d",
							id
						)
					)
				);
			}

			return ok!(QueueType*, QixException)(q);
		}

		// TODO: In future version let's add:
		//
		// 2. receive(QueueKey, T)
		// 4. wait(QueueKey)
		// 6. wait(QueueKey, Duration)
		//

		/** 
		 * Pushes a new message into the queue,
		 * waking up one of the threads currently
		 * blocking to dequeue an item from it
		 *
		 * Params:
		 *   id = the queue's id
		 *   item = the item to enqueue
		 * Returns: a `Result` either containing
		 * a boolean flag about whether the admit
		 * policy allowed the enqueueing to occur
		 * or a `QixException` if the id does not
		 * refer to a queue registered with this
		 * manager
		 */
		public Result!(bool, QixException) receive(QueueKey id, Item item)
		{
			auto q_r = getQueue(id);
			if(!q_r)
			{
				return error!(QixException, bool)(q_r.error());
			}

			auto q = q_r.ok();
			return ok!(bool, QixException)(q.receive(item));
		}

		/** 
		 * Wait indefinately to dequeue an item
		 * from the queue given by the provided
		 * id
		 *
		 * Params:
		 *   id = the queue's id
		 * Returns: a `Result` either containing
		 * the dequeued item or a `QixException`
		 * if the id does not refer to a queue
		 * registered with this manager
		 */
		public Result!(Item, QixException) wait(QueueKey id)
		{
			return wait(id, Duration.zero);
		}

		import std.datetime : Duration;

		/** 
		 * Wait up until a specified maximum
		 * amount of time to dequeue an item
		 * from the queue given by the provided
		 * id
		 *
		 * Params:
		 *   id = the queue's id
		 *   timeout = the maximum time to wait
		 * whilst blocking/waiting to dequeue
		 * an item from the queue
		 * Returns: a `Result` either containing
		 * the dequeued item or a `QixException`
		 * if the id does not refer to a queue
		 * registered with this manager or the
		 * timeout was exceeded
		 */
		public Result!(Item, QixException) wait(QueueKey id, Duration timeout)
		{
			auto q_r = getQueue(id);
			if(!q_r)
			{
				return error!(QixException, Item)(q_r.error());
			}

			auto q = q_r.ok();
			return q.wait(timeout);
		}
	}
}

unittest
{
	// item type
	struct Message
	{
		private string _t;
		this(string t)
		{
			this._t = t;
		}

		public string t()
		{
			return this._t;
		}
	} 
	
	// queue manager for queues that hold messages
	auto m = new Manager!(Message)();

	// no queues present
	assert(m.removeQueue(0) == false);
	assert(m.removeQueue(1) == false);

	// create two new queues
	Result!(Queue!(Message)*, string) q1_r = m.newQueue();
	Result!(Queue!(Message)*, string) q2_r = m.newQueue();

	assert(q1_r.is_okay());
	assert(q2_r.is_okay());
	auto q1 = q1_r.ok();
	auto q2 = q2_r.ok();

	// enqueue two messages, one per queue, then read them off
	//
	// we won't block as the messages are already arrived
	Message m1_in = Message("First message");
	Message m2_in = Message("Second message");
	assert(m.receive(q1.id(), m1_in)); // (indirect usage via manager) should not be rejected
	assert(q2.receive(m2_in)); // (direct usage via queue itself) should not be rejected
	assert(q1.wait() == m1_in); // should be the same message we sent in
	assert(q2.wait() == m2_in); // should be the same message we sent in

	// remove queues
	assert(m.removeQueue(q1)); // by QueueType*
	assert(m.removeQueue(q2.id())); // by id

	// handle nulls for queue removal
	assert(m.removeQueue(null) == false);

	// no queues present
	assert(m.removeQueue(0) == false);
	assert(m.removeQueue(1) == false);
}
