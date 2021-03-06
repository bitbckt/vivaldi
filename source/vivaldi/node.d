module vivaldi.node;

import vivaldi.coordinate;

/**
 * A node is a point in the coordinate system with an estimated
 * position.
 *
 * Node positions may either be represented Vivaldi coordinate, or by
 * "hybrid" coordinates. In the hybrid model, an additional
 * non-Euclidean adjustment term is added to each coordinate.
 *
 * Adjustment terms improve the performance of the Euclidean
 * embedding, and therefore can match the performance of
 * high-dimension embeddings with fewer dimensions (plus the
 * adjustment term).
 *
 * See "On Suitability of Euclidean Embedding forHost-based Network
 * Coordinate System" by Lee et al.
 *
 * Params:
 *      T = The type of an instantiation of Coordinate.
 *      window = The number of samples used to compute each adjustment term.
 */
struct Node(T, ushort window = 0)
{
    nothrow @safe @nogc:

    /**
     * Given a round-trip time observation for another node at
     * `other`, updates the estimated position of this Coordinate.
     */
    void update(const ref Node other, const double rttSeconds) {
        static if (window > 0) {
            import std.algorithm : sum;

            coordinate.update(other.coordinate, rttSeconds, adjustment, other.adjustment);
            const dist = coordinate.distanceTo(other.coordinate);

            // NOTE: Rather than choosing landmarks as described in
            // "On Suitability", sample all nodes. In a passive
            // system, this is feasible.
            samples[index] = rttSeconds - dist;
            index = (index + 1) % window;

            adjustment = sum(samples[]) / (2.0 * window);
        } else {
            coordinate.update(other.coordinate, rttSeconds);
        }
    }

    /**
     * Returns the distance to `other` in estimated round-trip time.
     */
    double distanceTo(const ref Node other) {
        auto dist = coordinate.distanceTo(other.coordinate);

        static if (window > 0) {
            import std.algorithm : max;
            dist = max(dist, dist + adjustment + other.adjustment);
        }

        return dist;
    }

    /**
     * The Vivaldi coordinate of this Node.
     */
    T coordinate;

private:

    static if (window > 0) {
        /**
         * The adjustment term in a hybrid coordinate system. See "On
         * Suitability" Sec. VI-A.
         */
        double adjustment = 0.0;

        /**
         * The insertion index for the next sample in the sample window.
         */
        size_t index = 0;

        /**
         * Samples is a ringbuffer of error terms used to compute an adjustment.
         */
        double[window] samples = 0.0;
    }
}

@("no adjustment")
nothrow @safe @nogc unittest {
    alias C4 = Coordinate!4;

    auto a = Node!C4();
    auto b = Node!C4();

    a.update(b, 0.2);
    assert(a.distanceTo(b) > 0);
}

@("adjustment")
nothrow @safe @nogc unittest {
    version (DigitalMars) {
        import std.math : isClose;
    } else version (LDC) {
        import std.math : approxEqual;
        alias isClose = approxEqual;
    }

    alias C3 = Coordinate!(3, 1.5, 0);

    auto a = Node!(C3, 20)();
    auto b = Node!(C3, 20)();

    a.coordinate.vector = [ -0.5, 1.3, 2.4 ];
    b.coordinate.vector = [ 1.2, -2.3, 3.4 ];

    assert(a.distanceTo(a) == 0);
    assert(a.distanceTo(b) == b.distanceTo(a));
    assert(isClose(a.distanceTo(b), 4.104875150354758));

    a.adjustment = -1.0e6;
    assert(isClose(a.distanceTo(b), 4.104875150354758));

    a.adjustment = 0.1;
    b.adjustment = 0.2;

    assert(isClose(a.distanceTo(b), 4.104875150354758 + 0.3));
}
