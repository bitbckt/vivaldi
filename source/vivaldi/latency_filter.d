module vivaldi.latency_filter;

import vivaldi.coordinate;

import std.container : DList;
import unit_threaded.runner.io;

/**
 * A helper for constructing and properly initializing a Buffer.
 */
private auto buffer(size_t window)() {
    Buffer!window* buf = new Buffer!window;

    foreach (i, ref node; buf.buffer) {
        node.prev = (i + window - 1) % window;
        node.next = (i + 1) % window;
    }

    return buf;
}

/**
 * Median filter based on Ekstrom, P. (2000, November). "Better Than
 * Average". _Embedded Systems Programming_, 100-110.
 *
 * Params:
 *      window = The number of data points in the filter window.
 */
private struct Buffer(size_t window)
     if (window > 0)
{
    struct Node {
        double value;
        size_t prev;
        size_t next;
    }

    Node[window] buffer;
    size_t cursor = 0;
    size_t head = 0;
    size_t median = 0;

    double push(double datum) nothrow @safe @nogc {
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

        buffer[cursor].value = float.nan;
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

    void insert(double datum, size_t index) nothrow @safe @nogc {
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
        auto buf = buffer!n;
        double[] output;

        foreach (i; input) {
            output ~= buf.push(i);
        }

        return output;
    }
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
 *      window = The size of the moving filter window.
 */
struct LatencyFilter(T, size_t window)
     if (window > 0)
{
    private alias B = Buffer!window;

    /**
     * Pushes a new latency datum into the filter window for a node,
     * and returns the current median value from the filter.
     */
    double push(T node, double rtt) @safe {
        import std.algorithm : sort;
        import std.math : isNaN;

        assert(!isNaN(rtt));

        B* buf = data.require(node, buffer!window);

        return buf.push(rtt);
    }

    /**
     * Returns the current median latency for a node. If no data has
     * been recorded for the node, returns NaN.
     */
    double get(T node) {
        B** p = node in data;

        if (p is null) {
            return float.nan;
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

    auto filter = new LatencyFilter!(string, 5);

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
