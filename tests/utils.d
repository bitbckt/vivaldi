module tests.utils;

import vivaldi;

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

    alias LF = LatencyFilter!(string, double, window);

    LF*[string] filters;

    for (uint cycle = 0; cycle < cycles; cycle++) {
        foreach (i, ref node; nodes) {
            const j = uniform(0, n);

            if (j != i) {
                const peer = nodes[j];
                const str = format("node_%d", j);

                auto filter = filters.require(format("node_%d", i), new LF);
                const rtt = filter.push(str, matrix[i][j]);

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
    double count = 0;

    for (size_t i = 0; i < n; i++) {
        for (size_t j = i + 1; j < n; j++) {
            const est = nodes[i].distanceTo(&nodes[j]);
            const actual = matrix[i][j];
            const err = abs(est - actual) / actual;

            stats.max = max(stats.max, err);
            stats.mean += err;
            count += 1;
        }
    }

    stats.mean /= count;
    return stats;
}
