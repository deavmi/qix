module qix.manager;

import qix.queue;
import niknaks.functional : Result, ok, error;
import std.string : format;
import gogga.mixins;


// max iterations when trying
// to find an unused queue id
private enum NEWQUEUE_MAX_ITER = 1000;

public template Manager(Item)
{
	public class Manager
	{
		import core.sync.mutex : Mutex;

		private alias QueueType = Queue!(Item);
		
		private QueueType[QueueKey] _q;
		private Mutex _ql; // todo: readers-writers lock

		this()
		{
			this._ql = new Mutex();
		}

		// result is either pointer to new queue
		// or... a string containing error as to
		// why there was a failure
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
	}
}

unittest
{
	struct Message{} // item type
	
	// queue manager for queues that hold messages
	auto m = new Manager!(Message);

	Result!(Queue!(Message)*, string) q1_r = m.newQueue();
	Result!(Queue!(Message)*, string) q2_r = m.newQueue();
	
}
