module vivaldi.latency_filter;

import vivaldi.coordinate;

import std.traits : isFloatingPoint;

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
    T min() nothrow @safe @nogc {
        return buffer[head].value;
    }

    /**
     * Returns the maximum datum within this buffer. If no data has
     * been pushed, returns NaN.
     */
    T max() nothrow @safe @nogc {
        import std.math : isNaN;

        auto cur = buffer[head].next;

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
    T push(T datum) nothrow @safe @nogc {
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
            // eventually end up in the middle.
            if ((i & 0x1) == 0x1 && !isNaN(buffer[cur].value)) {
                median = buffer[median].next;
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
            median = buffer[median].prev;
        }

        // If the window is a multiple of 2, shift the median backward
        // such that it points to the smaller of the two median
        // values.
        static if (window % 2 == 0) {
            median = buffer[median].prev;
        }

        cursor = (cursor + 1) % window;

        assert(!isNaN(buffer[median].value));
        return buffer[median].value;
    }

    void insert(T datum, size_t index) nothrow @safe @nogc {
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
    double[] output = [10, 10, 20, 20, 30, 30, 20];

    assert(compute!4(input) == output);
}

@("single peak 5")
unittest {
    double[] input = [10, 20, 30, 100, 30, 20, 10];
    double[] output = [10, 10, 20, 20, 30, 30, 30];

    assert(compute!5(input) == output);
}

@("single valley 4")
unittest {
    double[] input = [90, 80, 70, 10, 70, 80, 90];
    double[] output = [90, 80, 80, 70, 70, 70, 70];

    assert(compute!4(input) == output);
}

@("single valley 5")
unittest {
    double[] input = [90, 80, 70, 10, 70, 80, 90];
    double[] output = [90, 80, 80, 70, 70, 70, 70];

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
    double[] output = [10, 10, 10, 10, 100, 100, 10];

    assert(compute!4(input) == output);
}

@("triple outlier 5")
unittest {
    double[] input = [10, 10, 100, 100, 100, 10, 10];
    double[] output = [10, 10, 10, 10, 100, 100, 100];

    assert(compute!5(input) == output);
}

@("quintuple outlier 4")
unittest {
    double[] input = [10, 100, 100, 100, 100, 100, 10];
    double[] output = [10, 10, 100, 100, 100, 100, 100];

    assert(compute!4(input) == output);
}

@("quintuple outlier 5")
unittest {
    double[] input = [10, 100, 100, 100, 100, 100, 10];
    double[] output = [10, 10, 100, 100, 100, 100, 100];

    assert(compute!5(input) == output);
}

@("alternating 4")
unittest {
    double[] input = [10, 20, 10, 20, 10, 20, 10];
    double[] output = [10, 10, 10, 10, 10, 10, 10];

    assert(compute!4(input) == output);
}

@("alternating 5")
unittest {
    double[] input = [10, 20, 10, 20, 10, 20, 10];
    double[] output = [10, 10, 10, 10, 10, 20, 10];

    assert(compute!5(input) == output);
}

@("ascending 4")
unittest {
    double[] input = [10, 20, 30, 40, 50, 60, 70];
    double[] output = [10, 10, 20, 20, 30, 40, 50];

    assert(compute!4(input) == output);
}

@("ascending 5")
unittest {
    double[] input = [10, 20, 30, 40, 50, 60, 70];
    double[] output = [10, 10, 20, 20, 30, 40, 50];

    assert(compute!5(input) == output);
}

@("descending 4")
unittest {
    double[] input = [70, 60, 50, 40, 30, 20, 10];
    double[] output = [70, 60, 60, 50, 40, 30, 20];

    assert(compute!4(input) == output);
}

@("descending 5")
unittest {
    double[] input = [70, 60, 50, 40, 30, 20, 10];
    double[] output = [70, 60, 60, 50, 50, 40, 30];

    assert(compute!5(input) == output);
}

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
     if (isFloatingPoint!U && window > 0)
{
    private alias B = Buffer!(U, window);

    /**
     * Pushes a new latency datum into the filter window for a node,
     * and returns the current median value from the filter.
     */
    U push(T node, U rtt) @safe {
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
    U get(T node) nothrow @safe @nogc {
        B** p = node in data;

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
    void discard(T node) nothrow @safe @nogc {
        data.remove(node);
    }

    /**
     * Clears the latency filter of all data collected.
     */
    void clear() nothrow {
        data.clear();
    }

private:
    B*[T] data;
}

@("latency filter")
unittest {
    import std.math : isNaN;

    auto filter = new LatencyFilter!(string, double, 5);

    double[] input = [3, 2, 4, 6, 5, 1];
    double[] output;

    foreach (i; input) {
        output ~= filter.push("10.0.0.1", i);
    }

    assert(output == [3, 2, 3, 3, 4, 4]);
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
