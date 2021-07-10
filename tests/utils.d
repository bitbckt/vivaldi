module tests.utils;

import vivaldi.latency_filter;
import vivaldi.node;

/**
 * Generates and zero-fills an NxN matrix.
 */
template matrix(size_t n) {
    auto matrix() {
        double[n][n] matrix;

        // XXX: Is there a better way to zero-fill a matrix?
        // memset(3)?
        foreach (ref row; matrix) {
            row[] = 0.0;
        }

        return matrix;
    }
}

/**
 * Runs a number of cycles using the provided nodes and a matrix of
 * true latencies among them.
 *
 * On each cycle, each node will choose a random peer and observe the
 * true round-trip time, updating its coordinate estimate.
 */
void simulate(T, size_t window, size_t n)(ref T[n] nodes, double[n][n] matrix, uint cycles)
    @safe
{

    import std.format;
    import std.random;

    auto filter = new LatencyFilter!(string, double, window);

    for (uint cycle = 0; cycle < cycles; cycle++) {
        foreach (i, ref node; nodes) {
            auto j = uniform(0, n);

            if (j != i) {
                auto peer = nodes[j];
                auto str = format("node_%d", j);
                const auto rtt = filter.push(str, matrix[i][j]);

                node.update(&peer, rtt);
            }
        }
    }
}

/**
 * Stats returned by evaluate().
 */
struct Stats {
    /**
     * The maximum observed error between a latency matrix and a simulation.
     */
    double max = 0.0;

    /**
     * The mean observed error between a latency matrix and a simulation.
     */
    double mean = 0.0;
}

/**
 * Evaluates the output of a simulation and a matrix of true
 * latencies, returning the maximum and mean error between the
 * simulated results and the truth.
 */
Stats* evaluate(T, size_t n)(T[n] nodes, double[n][n]matrix) nothrow @safe {
    import std.algorithm : max;
    import std.math : abs;

    auto stats = new Stats;
    uint count = 0;

    for (size_t i = 0; i < n; i++) {
        for (size_t j = i + 1; j < n; j++) {
            const double est = nodes[i].distanceTo(&nodes[j]);
            const double actual = matrix[i][j];
            const double err = abs(est - actual) / actual;

            stats.max = max(stats.max, err);
            stats.mean += err;
            count += 1;
        }
    }

    stats.mean /= cast(double)count;
    return stats;
}
