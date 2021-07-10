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
 */
struct Node(T, size_t window = 0)
{
    /**
     * Given a round-trip time observation for another node at
     * `other`, updates the estimated position of this Coordinate.
     */
    void update(const Node* other, double rtt) nothrow @safe @nogc {
        coordinate.update(&other.coordinate, rtt);

        static if (window > 0) {
            const auto dist = coordinate.distanceTo(&other.coordinate);

            // NOTE: Rather than choosing landmarks as described in
            // "On Suitability", sample all nodes. In a passive
            // system, this is feasible.
            samples[index] = rtt - dist;
            index = (index + 1) % window;

            double sum = 0.0;

            foreach (i; samples) {
                sum += i;
            }

            adjustment = sum / (2.0 * cast(double)window);
        }
    }

    /**
     * Returns the distance to `other` in estimated round-trip time.
     */
    double distanceTo(const Node* other) nothrow @safe @nogc {
        auto dist = coordinate.distanceTo(&other.coordinate);

        static if (window > 0) {
            // NB. adjustment is in seconds
            const double adj = adjustment + other.adjustment;

            const auto adjusted = dist + adj;

            if (adjusted > 0) {
                dist = adjusted;
            }
        }

        return dist;
    }

private:
    T coordinate;

    static if (window > 0) {
        double adjustment = 0.0;
        size_t index = 0;
        double[window] samples = 0.0;
    }
}

@("no adjustment")
nothrow @safe @nogc unittest {
    alias C4 = Coordinate!4;

    auto a = Node!C4();
    auto b = Node!C4();

    a.update(&b, 0.2);
    assert(a.distanceTo(&b) > 0);
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

    assert(a.distanceTo(&a) == 0);
    assert(a.distanceTo(&b) == b.distanceTo(&a));
    assert(isClose(a.distanceTo(&b), 4.104875150354758));

    a.adjustment = -1.0e6;
    assert(isClose(a.distanceTo(&b), 4.104875150354758));

    a.adjustment = 0.1;
    b.adjustment = 0.2;

    assert(isClose(a.distanceTo(&b), 4.104875150354758 + 0.3));
}
