module qix.queue;

public alias QueueKey = size_t;

public struct Queue
{
	private QueueKey _id;

	package this(QueueKey id)
	{
		this._id = id;
	}

	public QueueKey id()
	{
		return this._id;
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
