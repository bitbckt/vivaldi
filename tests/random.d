module tests.random;

import tests.utils;
import vivaldi.coordinate;
import vivaldi.node;

private static enum NanosPerSecond = 1.0e9;

/**
 * Generates an NxN matrix of latencies using a randomized normal
 * distribution.
 */
template random(size_t n, double mean, double stddev) {

    import mir.random;
    import mir.random.variable;

    auto random() {
        Random gen = Random(1);
        auto rv = NormalVariable!double(mean, stddev);
        auto matrix = new double[n][n];

        for (size_t i = 0; i < n; i++) {
            for (size_t j = i + 1; j < n; j++) {
                const double rtt = rv(gen);

                matrix[i][j] = rtt;
                matrix[j][i] = rtt;
            }
        }

        return matrix;
    }
}

@("random")
unittest {
    import std.random;

    // Stable seed for random unitvectors.
    rndGen().seed(1);

    alias N = Node!(Coordinate!8, 20);

    immutable double mean = 0.1;
    immutable double stddev = 0.01;
    immutable size_t n = 25;
    auto cycles = 1000;

    N[n] nodes = new N[n];
    double[n][n] matrix = random!(n, mean, stddev)();

    simulate!(N, 3, n)(nodes, matrix, cycles);
    evaluate!(N, n)(nodes, matrix);
}
