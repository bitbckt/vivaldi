module tests.linear;

import tests.utils;
import vivaldi;

/**
 * Generates an NxN matrix of latencies in a straight line, a fixed
 * distance apart.
 */
template linear(size_t n, double distance) {
    auto linear() nothrow @safe @nogc {
        auto matrix = matrix!n;

        for (size_t i = 0; i < n; i++) {
            for (size_t j = i + 1; j < n; j++) {
                const rtt = (j - i) * distance;

                matrix[i][j] = rtt;
                matrix[j][i] = rtt;
            }
        }

        return matrix;
    }
}

@("linear")
unittest {
    import std.format;
    import std.random;

    // Stable seed for random unitvectors.
    rndGen().seed(1);

    alias N = Node!(Coordinate!8, 20);

    immutable distance = 0.01;
    immutable n = 10;
    immutable cycles = 1000;

    N[n] nodes = new N[n];
    double[n][n] matrix = linear!(n, distance);

    simulate!(N, 3, n)(nodes, matrix, cycles);
    auto stats = evaluate!(N, n)(nodes, matrix);

    assert(stats.mean <= 0.0025, format("mean=%s", stats.mean));
    assert(stats.max <= 0.01, format("max=%s", stats.max));
}
