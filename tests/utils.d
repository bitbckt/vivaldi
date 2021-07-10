module tests.utils;

import vivaldi.latency_filter;
import vivaldi.node;

/**
 * Runs a number of cycles using the provided notes and a matrix of
 * true latencies among them.
 *
 * On each cycle, each node will choose a random peer and observe the
 * true round-trip time, updating its coordinate estimate.
 */
void simulate(T, size_t window, size_t n)(return ref T[n] nodes, double[n][n]matrix, uint cycles) {
    import mir.random;
    import mir.random.variable;
    import std.format;

    Random gen = Random(1);
    auto filter = new LatencyFilter!(string, double, window);

    for (uint cycle = 0; cycle < cycles; cycle++) {
        foreach (size_t i, _; nodes) {
            auto rv = UniformVariable!size_t(0, n - 1);
            auto j = rv(gen);

            if (j != i) {
                auto node = nodes[j];
                auto str = format("node_%d", j);
                const auto rtt = filter.push(str, matrix[i][j]);

                nodes[j].update(&node, rtt);
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
Stats* evaluate(T, size_t n)(T[n] nodes, double[n][n]matrix) {
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
