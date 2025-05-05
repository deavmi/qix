module qix.queue;

package alias QueueKey = size_t;

public struct Queue
{
	private QueueKey _id;

	package this(QueueKey id)
	{
		this._id = id;
	}

	
}
