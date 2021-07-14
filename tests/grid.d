module tests.grid;

import tests.utils;
import vivaldi;

/**
 * Generates an NxN matrix of latencies in a 2D grid, a fixed distance
 * apart.
 */
template grid(size_t n, double distance) {
    import std.math : sqrt;

    auto grid() nothrow @safe @nogc {
        auto matrix = matrix!n;

        const dim = sqrt(cast(double)n);

        for (size_t i = 0; i < n; i++) {
            for (size_t j = i + 1; j < n; j++) {
                const x1 = i % dim;
                const y1 = i / dim;
                const x2 = j % dim;
                const y2 = j / dim;

                const dx = x2 - x1;
                const dy = y2 - y1;

                const z = sqrt(dx*dx + dy*dy);

                const double rtt = z * distance;

                matrix[i][j] = rtt;
                matrix[j][i] = rtt;
            }
        }

        return matrix;
    }
}

@("grid")
unittest {
    import std.format;
    import std.random;

    // Stable seed for random unitvectors.
    rndGen().seed(1);

    alias N = Node!(Coordinate!8, 20);

    immutable distance = 0.01;
    immutable size_t n = 25;
    auto cycles = 1000;

    N[n] nodes = new N[n];
    double[n][n] matrix = grid!(n, distance);

    simulate!(N, 3, n)(nodes, matrix, cycles);
    auto stats = evaluate!(N, n)(nodes, matrix);

    assert(stats.mean <= 0.0015, format("mean=%s", stats.mean));
    assert(stats.max <= 0.022, format("max=%s", stats.max));
}
