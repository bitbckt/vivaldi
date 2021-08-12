module tests.drift;

import tests.utils;
import vivaldi;

@("drift")
unittest {
    import std.algorithm : map, max, min, sum;
    import std.format;
    import std.math;
    import std.random;

    // Stable seed for random unitvectors.
    rndGen().seed(1);

    alias N = Node!(Coordinate!2, 20);

    immutable double dist = 0.5;
    immutable size_t n = 4;

    N[n] nodes = new N[n];

    nodes[0].coordinate.vector = [ 0.0, 0.0 ];
    nodes[1].coordinate.vector = [ 0.0, dist ];
    nodes[2].coordinate.vector = [ dist, dist ];
    nodes[3].coordinate.vector = [ dist, 0.0 ];

    auto matrix = matrix!n;

    // The nodes are laid out like this so the distances are all
    // equal, except for the diagonal:
    //
    // (1)  <- dist ->  (2)
    //
    //  | <- dist        |
    //  |                |
    //  |        dist -> |
    //
    // (0)  <- dist ->  (3)
    for (size_t i = 0; i < n; i++) {
        for (size_t j = i + 1; j < n; j++) {
            double rtt = dist;

            if (i % 2 == 0 && j % 2 == 0) {
                rtt *= SQRT2;
            }

            matrix[i][j] = rtt;
            matrix[j][i] = rtt;
        }
    }

    double centerError() {
        auto mini = nodes[0].coordinate;
        auto maxi = nodes[0].coordinate;

        for (size_t i = 1; i < n; i++) {
            auto coord = nodes[i].coordinate;

            foreach (j, v; coord.vector) {
                mini.vector[j] = min(mini.vector[j], v);
                maxi.vector[j] = max(maxi.vector[j], v);
            }
        }

        auto mid = new double[2];

        for (size_t i = 0; i < 2; i++) {
            mid[i] = mini.vector[i] + (maxi.vector[i] - mini.vector[i]) / 2;
        }

        return sqrt(sum(mid.map!(a => a * a)));
    }

    simulate!(N, 3, n)(nodes, matrix, 1000);
    const baseline = centerError();

    simulate!(N, 3, n)(nodes, matrix, 10_000);

    const err = centerError();
    assert(err <= 0.81 * baseline, format("err=%s baseline=%s", err, baseline));
}
