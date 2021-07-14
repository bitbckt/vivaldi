module tests.cluster;

import tests.utils;
import vivaldi;

/**
 * Generates an NxN matrix of latencies clustered on either side of a
 * split. Nodes on either side of split have "local" latency amongst
 * themselves, and an additional "remote" latency with nodes on the
 * opposite side.
 */
template cluster(size_t n, double local, double remote) {

    auto cluster() nothrow @safe @nogc {
        auto matrix = matrix!n;

        const split = n / 2;
        for (size_t i = 0; i < n; i++) {
            for (size_t j = i + 1; j < n; j++) {
                double rtt = local;

                if ((i <= split && j > split) || (i > split && j <= split)) {
                    rtt += remote;
                }

                matrix[i][j] = rtt;
                matrix[j][i] = rtt;
            }
        }

        return matrix;
    }
}

@("cluster")
unittest {
    import std.format;
    import std.random;

    // Stable seed for random unitvectors.
    rndGen().seed(1);

    alias N = Node!(Coordinate!8, 20);

    immutable double local = 0.001;
    immutable double remote = 0.01;
    immutable size_t n = 25;
    auto cycles = 1000;

    N[n] nodes = new N[n];
    double[n][n] matrix = cluster!(n, local, remote);

    simulate!(N, 3, n)(nodes, matrix, cycles);
    auto stats = evaluate!(N, n)(nodes, matrix);

    assert(stats.mean <= 0.00006, format("mean=%s", stats.mean));
    assert(stats.max <= 0.00048, format("max=%s", stats.max));
}
