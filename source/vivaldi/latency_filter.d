module vivaldi.latency_filter;

import vivaldi.coordinate;

import std.traits;

/**
 * A helper for constructing and properly initializing a Buffer.
 */
private auto buffer(T, size_t window)()
{
    auto buf = new Buffer!(T, window);
    buf.initialize();
    return buf;
}

/**
 * Median filter based on "Better Than Average" by Paul Ekstrom.
 *
 * By combining a ring buffer with a sorted linked list, this
 * implementation offers O(n) complexity. A naive implementation which
 * requires sorting the window is O(n^2).
 *
 * Params:
 *      T = The datum type.
 *      window = The number of data points in the filter window.
 */
private struct Buffer(T, size_t window)
     if (isFloatingPoint!(T) && window > 0)
{
    struct Node {
        T value;
        size_t prev;
        size_t next;
    }

    Node[window] buffer;

    // Cursor points at the next insertion point in the ring buffer.
    size_t cursor = 0;

    // Head points at the smallest value in the linked list.
    size_t head = 0;

    // Median points at the median value.
    size_t median = 0;

    /**
     * Initializes the linked list and sets the ringbuffer values to NaN.
     *
     * This method must be called prior to `push`, but may be called
     * again to reset the state of the buffer.
     */
    void initialize() nothrow @safe @nogc {
        foreach (i, ref node; buffer) {
            node.value = T.nan;
            node.prev = (i + window - 1) % window;
            node.next = (i + 1) % window;
        }
    }

    /**
     * Returns the minimum datum within this buffer. If no data has
     * been pushed, returns NaN.
     */
    T min() const pure nothrow @safe @nogc {
        return buffer[head].value;
    }

    /**
     * Returns the maximum datum within this buffer. If no data has
     * been pushed, returns NaN.
     */
    T max() const pure nothrow @safe @nogc {
        import std.math : isNaN;

        size_t cur = buffer[head].next;

        while (!isNaN(buffer[cur].value) && cur != head) {
            cur = buffer[cur].next;
        }

        auto prev = buffer[cur].prev;
        return buffer[prev].value;
    }

    /**
     * Pushes a new datum into the ring buffer, and updates the head
     * and median indexes.
     *
     * Returns the median after the datum has been pushed.
     */
    T push(const T datum) pure nothrow @safe @nogc {
        import std.math : isNaN;

        // If the current head will be overwritten, move it to the
        // next node.
        if (cursor == head) {
            head = buffer[head].next;
        }

        // Remove the node at cursor; it will be overwritten.

        auto pred = buffer[cursor].prev;
        auto succ = buffer[cursor].next;

        buffer[pred].next = succ;

        buffer[cursor].value = T.nan;
        buffer[cursor].prev = size_t.max;
        buffer[cursor].next = size_t.max;

        buffer[succ].prev = pred;

        // Point the median at the minimum value in the list.
        median = head;

        auto cur = head;
        auto inserted = false;

        for (size_t i = 0; i < window; i++) {
            if (!inserted) {
                auto shouldInsert = true;

                if (!isNaN(buffer[cur].value)) {
                    shouldInsert = (i + 1 == window) ||
                        buffer[cur].value >= datum;
                }

                if (shouldInsert) {
                    // Insert the removed node with its new value.
                    insert(datum, cur);
                    inserted = true;
                }
            }

            // Shift the median on every other node. It will
            // eventually end up in the middle. This is similar to
            // Floyd's "tortoise and hare" cycle detection
            // algorithm. Here, i is the hare, and the median pointer
            // is the tortoise.
            if (i % 2 == 1) {
                median = buffer[median].next;
            }

            // Break once an unallocated node has been reached.
            if (isNaN(buffer[cur].value)) {
                break;
            }

            cur = buffer[cur].next;
        }

        auto hd = buffer[head].value;
        auto updateHead = true;

        // Update the head if the new datum is the minimum value.
        if (!isNaN(hd)) {
            updateHead = datum <= hd;
        }

        if (updateHead) {
            head = cursor;
            // Move the median pointer back if a new minimum was
            // inserted.
            median = buffer[median].prev;
        }

        cursor = (cursor + 1) % window;

        assert(!isNaN(buffer[median].value));
        return buffer[median].value;
    }

    void insert(const T datum, const size_t index) pure nothrow @safe @nogc {
        const auto succ = index;
        const auto pred = buffer[index].prev;

        static if (window > 1) {
            assert(index != cursor);
        }

        buffer[pred].next = cursor;

        buffer[cursor].value = datum;
        buffer[cursor].prev = pred;
        buffer[cursor].next = succ;

        buffer[succ].prev = cursor;
    }
}

version(unittest) {
    double[] compute(size_t n)(const double[] input) {
        import std.algorithm;
        import std.math : isNaN;

        auto buf = buffer!(double, n);
        double[] output;

        foreach (i; input) {
            output ~= buf.push(i);

            version (LDC) {
                const auto expected = buf.buffer.dup
                    .filter!(a => !isNaN(a.value)) // min(NaN, ...) == NaN on LDC.
                    .map!(a => a.value)
                    .reduce!min;
            } else {
                const auto expected = buf.buffer.dup
                    .map!(a => a.value)
                    .reduce!min;
            }

            assert(buf.min == expected);
            assert(buf.max == buf.buffer.dup.map!(a => a.value).reduce!max);
        }

        return output;
    }
 }

@("attributes")
nothrow @safe @nogc unittest {
    auto buf = Buffer!(double, 4)();

    buf.initialize();

    assert(buf.push(10) == 10);
    assert(buf.min == 10);
    assert(buf.max == 10);
}

@("single peak 4")
unittest {
    double[] input = [10, 20, 30, 100, 30, 20, 10];
    double[] output = [10, 20, 20, 30, 30, 30, 30];

    assert(compute!4(input) == output);
}

@("single peak 5")
unittest {
    double[] input = [10, 20, 30, 100, 30, 20, 10];
    double[] output = [10, 20, 20, 30, 30, 30, 30];

    assert(compute!5(input) == output);
}

@("single valley 4")
unittest {
    double[] input = [90, 80, 70, 10, 70, 80, 90];
    double[] output = [90, 90, 80, 80, 70, 70, 80];

    assert(compute!4(input) == output);
}

@("single valley 5")
unittest {
    double[] input = [90, 80, 70, 10, 70, 80, 90];
    double[] output = [90, 90, 80, 80, 70, 70, 70];

    assert(compute!5(input) == output);
}

@("single outlier 4")
unittest {
    double[] input = [10, 10, 10, 100, 10, 10, 10];
    double[] output = [10, 10, 10, 10, 10, 10, 10];

    assert(compute!4(input) == output);
}

@("single outlier 5")
unittest {
    double[] input = [10, 10, 10, 100, 10, 10, 10];
    double[] output = [10, 10, 10, 10, 10, 10, 10];

    assert(compute!5(input) == output);
}

@("triple outlier 4")
unittest {
    double[] input = [10, 10, 100, 100, 100, 10, 10];
    double[] output = [10, 10, 10, 100, 100, 100, 100];

    assert(compute!4(input) == output);
}

@("triple outlier 5")
unittest {
    double[] input = [10, 10, 100, 100, 100, 10, 10];
    double[] output = [10, 10, 10, 100, 100, 100, 100];

    assert(compute!5(input) == output);
}

@("quintuple outlier 4")
unittest {
    double[] input = [10, 100, 100, 100, 100, 100, 10];
    double[] output = [10, 100, 100, 100, 100, 100, 100];

    assert(compute!4(input) == output);
}

@("quintuple outlier 5")
unittest {
    double[] input = [10, 100, 100, 100, 100, 100, 10];
    double[] output = [10, 100, 100, 100, 100, 100, 100];

    assert(compute!5(input) == output);
}

@("alternating 4")
unittest {
    double[] input = [10, 20, 10, 20, 10, 20, 10];
    double[] output = [10, 20, 10, 20, 20, 20, 20];

    assert(compute!4(input) == output);
}

@("alternating 5")
unittest {
    double[] input = [10, 20, 10, 20, 10, 20, 10];
    double[] output = [10, 20, 10, 20, 10, 20, 10];

    assert(compute!5(input) == output);
}

@("ascending 4")
unittest {
    double[] input = [10, 20, 30, 40, 50, 60, 70];
    double[] output = [10, 20, 20, 30, 40, 50, 60];

    assert(compute!4(input) == output);
}

@("ascending 5")
unittest {
    double[] input = [10, 20, 30, 40, 50, 60, 70];
    double[] output = [10, 20, 20, 30, 30, 40, 50];

    assert(compute!5(input) == output);
}

@("descending 4")
unittest {
    double[] input = [70, 60, 50, 40, 30, 20, 10];
    double[] output = [70, 70, 60, 60, 50, 40, 30];

    assert(compute!4(input) == output);
}

@("descending 5")
unittest {
    double[] input = [70, 60, 50, 40, 30, 20, 10];
    double[] output = [70, 70, 60, 60, 50, 40, 30];

    assert(compute!5(input) == output);
}

/**
 * Tests whether a type K is suitable for use as a hash key, under the following
 * constraints:
 *   - is it a non-void scalar type?
 *   - is it a string/char[]/wchar[]?
 *   - is it a struct or class which implements size_t toHash and bool opEquals?
 */
private enum bool isHashKey(K) =
    (!is(K : void) &&
     isBasicType!(K)) ||
    isNarrowString!(K) ||
    (isAggregateType!(K) &&
     is(ReturnType!((K k) => k.toHash) == size_t) &&
     is(ReturnType!((K k) => k.opEquals(k)) == bool));

/**
 * A latency filter tracks a stream of latency measurements involving
 * a remote node, and returns an expected latency value using a moving
 * median filter.
 *
 * Filter buffers for each node are allocated on the GC heap, but
 * operate in constant space thereafter.
 *
 * See "Network Coordinates in the Wild" by Jonathan Ledlie, Paul
 * Gardner, and Margo Seltzer, Section 7.2.
 *
 * Params:
 *      T = The node type.
 *      U = The datum type.
 *      window = The size of the moving filter window.
 */
struct LatencyFilter(T, U, size_t window)
     if (isHashKey!T && isFloatingPoint!U && window > 0)
{
    private alias B = Buffer!(U, window);

    /**
     * Pushes a new latency datum into the filter window for a node,
     * and returns the current median value from the filter.
     */
    U push(const T node, const U rtt) @safe {
        import std.algorithm : sort;
        import std.math : isNaN;

        assert(!isNaN(rtt));

        B* buf = data.require(node, buffer!(U, window));

        return buf.push(rtt);
    }

    /**
     * Returns the current median latency for a node. If no data has
     * been recorded for the node, returns NaN.
     */
    U get(const T node) const pure nothrow @safe @nogc {
        const(B*)* p = node in data;

        if (p is null) {
            return U.nan;
        }

        auto buf = *p;

        // NB. This may return NaN if a buffer has been allocated, but
        // no data has been recorded.
        return buf.buffer[buf.median].value;
    }

    /**
     * Discards data collected for a node.
     */
    void discard(const T node) nothrow @safe @nogc {
        data.remove(node);
    }

    /**
     * Clears the latency filter of all data collected.
     */
    void clear() nothrow {
        data.clear();
    }

private:

    B*[const(T)] data;
}

@("type parameters")
unittest {
    class A;
    struct B;

    class C {
        override size_t toHash() nothrow {
            return 42;
        }

        override bool opEquals(Object o) {
            return false;
        }
    }

    struct D {
        size_t toHash() const @safe pure nothrow {
            return 42;
        }

        bool opEquals(ref const D s) const @safe pure nothrow {
            return false;
        }
    }

    assert(!__traits(compiles, new LatencyFilter!(void, double, 5)));
    assert(__traits(compiles, new LatencyFilter!(int, double, 5)));
    assert(__traits(compiles, new LatencyFilter!(float, double, 5)));
    assert(__traits(compiles, new LatencyFilter!(char, double, 5)));

    // A bit non-sensical, but sure.
    assert(__traits(compiles, new LatencyFilter!(bool, double, 5)));

    assert(__traits(compiles, new LatencyFilter!(string, double, 5)));
    assert(__traits(compiles, new LatencyFilter!(char[], double, 5)));
    assert(__traits(compiles, new LatencyFilter!(wchar[], double, 5)));
    assert(!__traits(compiles, new LatencyFilter!(dchar[], double, 5)));

    assert(!__traits(compiles, new LatencyFilter!(A, double, 5)));
    assert(!__traits(compiles, new LatencyFilter!(B, double, 5)));
    assert(__traits(compiles, new LatencyFilter!(C, double, 5)));
    assert(__traits(compiles, new LatencyFilter!(D, double, 5)));

    assert(!__traits(compiles, new LatencyFilter!(string, int, 5)));
    assert(__traits(compiles, new LatencyFilter!(string, float, 5)));
    assert(__traits(compiles, new LatencyFilter!(string, double, 5)));
    assert(__traits(compiles, new LatencyFilter!(string, real, 5)));

    assert(__traits(compiles, new LatencyFilter!(string, double, 1)));
    assert(!__traits(compiles, new LatencyFilter!(string, double, 0)));
}

@("usage")
unittest {
    import std.math : isNaN;

    auto filter = new LatencyFilter!(string, double, 5);

    double[] input = [3, 2, 4, 6, 5, 1];
    double[] output;

    foreach (i; input) {
        output ~= filter.push("10.0.0.1", i);
    }

    assert(output == [3, 3, 3, 4, 4, 4]);
    assert(filter.get("10.0.0.1") == 4);

    filter.push("10.0.0.2", 100);
    assert(filter.get("10.0.0.2") == 100);

    filter.discard("10.0.0.1");
    assert(isNaN(filter.get("10.0.0.1")));
    assert(!isNaN(filter.get("10.0.0.2")));

    filter.clear();
    assert(isNaN(filter.get("10.0.0.1")));
    assert(isNaN(filter.get("10.0.0.2")));
}

@("push attributes")
@safe unittest {
    auto filter = new LatencyFilter!(string, double, 5);

    filter.push("10.0.0.1", 42);
}

@("get/discard attributes")
nothrow @safe @nogc unittest {
    import std.math : isNaN;

    auto filter = LatencyFilter!(string, double, 5)();

    assert(isNaN(filter.get("10.0.0.1")));

    filter.discard("10.0.0.1");
}

@("clear attributes")
nothrow unittest {
    auto filter = LatencyFilter!(string, double, 5)();
    filter.clear();
}
