/**
 * Exception type definitions
 */
module qix.exceptions;

/**
 * The base Qix exception type
 * from where all others derive
 */
public abstract class QixException : Exception
{
	// TODO: Document (if this shows uo in dub docs)
	package this(string m)
	{
		super("QixException: "~m);
	}
}
