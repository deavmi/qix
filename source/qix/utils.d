/**
 * Helper routines
 *
 * Authors: Tristan Brice Velloza Kildaire (deavmi)
 */
module qix.utils;

import std.random : rndGen, Random;

// thread-local random number generator
//
// (each thread will have its own seed)
private Random r_tls;
static this()
{
	r_tls = rndGen();
}

/** 
 * Generates a random number
 * within the `size_t` range.
 *
 * This uses a random number
 * generator that is unique
 * to the calling thread (TLS).
 *
 * Returns: a random number
 */
package size_t rand()
{
	alias r = r_tls;
	size_t n = r.front();
	r.popFront();

	return n;
}

version(unittest)
{
	import gogga.mixins;	
}

unittest
{
	DEBUG("random: ", rand());
	DEBUG("random: ", rand());
	DEBUG("random: ", rand());
	DEBUG("random: ", rand());
}
