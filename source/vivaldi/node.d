module vivaldi.node;

import vivaldi.coordinate;

import core.time;

private static enum NanosPerSecond = 1.0e9;

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
    void update(const Node* other, const Duration rtt) nothrow @safe @nogc {
        coordinate.update(&other.coordinate, rtt);

        static if (window > 0) {
            const auto dist = coordinate.distanceTo(&other.coordinate);

            // NOTE: Rather than choosing landmarks as described in
            // "On Suitability", sample all nodes. In a passive
            // system, this is feasible.
            samples[index] = (rtt - dist).total!"nsecs" / NanosPerSecond;
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
    Duration distanceTo(const Node* other) nothrow @safe @nogc {
        auto dist = coordinate.distanceTo(&other.coordinate);

        static if (window > 0) {
            // NB. adjustment is in seconds
            const double adj = adjustment + other.adjustment;

            const auto adjusted = dist + nsecs(cast(long)(adj * NanosPerSecond));

            if (adjusted.total!"nsecs" > 0) {
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

    a.update(&b, msecs(200));
    assert(a.distanceTo(&b) > msecs(0));
}

@("adjustment")
nothrow @safe @nogc unittest {
    alias C4 = Coordinate!4;

    auto a = Node!(C4, 10)();
    auto b = Node!(C4, 10)();

    a.update(&b, msecs(200));
    assert(a.distanceTo(&b) > a.coordinate.distanceTo(&b.coordinate));
}
