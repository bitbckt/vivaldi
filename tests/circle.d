module tests.circle;

import tests.utils;
import vivaldi;

/**
 * Generates an NxN matrix with a nodes evenly distributed around a
 * circle with the given radius, and an additional node at the center
 * of the circle, one extra radius away from the others.
 *
 * The extra radius should cause the central node to have a larger
 * "height" than the others.
 */
template circle(size_t n, double radius) {

    import std.math;

    auto circle() nothrow @safe @nogc {
        auto matrix = matrix!n;

        for (size_t i = 0; i < n; i++) {
            for (size_t j = i + 1; j < n; j++) {
                double rtt;

                if (i == 0) {
                    rtt = 2 * radius;
                } else {
                    const t1 = 2.0 * PI * i / n;
                    const x1 = cos(t1);
                    const y1 = sin(t1);

                    const t2 = 2.0 * PI * j / n;
                    const x2 = cos(t2);
                    const y2 = sin(t2);

                    const dx = x2 - x1;
                    const dy = y2 - y1;

                    const dist = hypot(dx, dy);

                    rtt = dist * radius;
                }

                matrix[i][j] = rtt;
                matrix[j][i] = rtt;
            }
        }

        return matrix;
    }
}

@("circle")
unittest {
    import std.format;
    import std.random;

    // Stable seed for random unitvectors.
    rndGen().seed(1);

    alias N = Node!(Coordinate!2, 20);

    immutable radius = 0.1;
    immutable n = 25;
    immutable cycles = 1000;

    N[n] nodes = new N[n];
    double[n][n] matrix = circle!(n, radius);
    simulate!(N, 3, n)(nodes, matrix, cycles);
    auto stats = evaluate!(N, n)(nodes, matrix);

    foreach (i, node; nodes) {
        auto c = node.coordinate;

        if (i == 0) {
            assert(c.height >= 0.97 * radius,
                   format("height=%s", c.height));
        } else {
            assert(c.height <= 0.03 * radius,
                   format("height=%s", c.height));
        }
    }

    assert(stats.mean <= 0.0086, format("mean=%s", stats.mean));
    assert(stats.max <= 0.12, format("max=%s", stats.max));
}
