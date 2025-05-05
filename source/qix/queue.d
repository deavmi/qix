module qix.queue;

package alias QueueKey = size_t;

public struct Queue
{
	private QueueKey _id;

	package this(QueueKey id)
	{
		this._id = id;
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
