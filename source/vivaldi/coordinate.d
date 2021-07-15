module vivaldi.coordinate;

import std.math : isFinite;

/**
 * A helper for validating a double lies within [0.0, 1.0).
 */
private bool isValid01(double v)() {
    return v >= 0.0 && v < 1.0;
}

/**
 * Coordinate represents a point in a Vivaldi network coordinate
 * system.
 *
 * A coordinate has two components: a Euclidean and a non-Euclidean
 * component.
 *
 * The Euclidean component represents the distance across the core of
 * the Internet, where link distance typically reflects geographic
 * distance.
 *
 * The non-Euclidean component is a "height" offset, which represents
 * the distance across an access link to the core Internet. Link
 * distance on access links is typically constrained by bandwidth and
 * congestion, rather than geography.
 *
 * See "Vivaldi: A Decentralized Network Coordinate System" by Dabek,
 * et al.
 *
 * Params:
 *      dims = Dimensionality of the coordinate system.
 *      maxError = Limit to the error any observation may induce.
 *      minHeight = The minimum height of any Coordinate.
 *      ce = A tuning factor which impacts the maximum impact an observation
 *           can have on a Coordinate.
 *      cc = ditto
 *      rho = A tuning factor for the effect of gravity exerted by the origin to
 *            control drift. See "Network Coordinates in the Wild" by
 *            Ledlie, et al. for more information.
 */
struct Coordinate(size_t dims,
                  double maxError = 1.5,
                  double minHeight = 1.0e-5,
                  double ce = 0.25,
                  double cc = 0.25,
                  double rho = 150.0)
     if (dims > 0 && isValid01!ce && isValid01!cc && isFinite(rho) && rho > 0.0)
{

    /**
     * Given a round-trip time observation for another node at
     * `other`, updates the estimated position of this Coordinate.
     *
     * The adjustment parameters are used for hybrid coordinates. See
     * Node.
     */
    void update(const ref Coordinate other,
                double rtt,
                const double localAdjustment = 0.0,
                const double remoteAdjustment = 0.0)
         nothrow @safe @nogc {

        import std.algorithm : max, min;
        import std.math : abs, pow;

        assert(isFinite(rtt));

        double dist = distanceTo(other);
        dist = max(dist, dist + localAdjustment + remoteAdjustment);

        // Protect against div-by-zero.
        rtt = max(rtt, double.min_normal);

        // This term is the relative error of this sample.
        const err = abs(dist - rtt) / rtt;

        // Weight is used to push in proportion to the error: large
        // error -> large force.
        const weight = error / max(error + other.error, double.min_normal);

        error = min(err * ce * weight + error * (1.0 - ce * weight), maxError);

        const delta = cc * weight;

        double force = delta * (rtt - dist);

        // Apply the force exerted by the other node.
        applyForce(other, force);

        scope origin = Coordinate();

        dist = distanceTo(origin);
        dist = max(dist, dist + localAdjustment);

        // Gravity toward the origin exerts a pulling force which is a
        // small fraction of the expected diameter of the network.
        // "Network Coordinates in the Wild", Sec. 7.2
        force = -1.0 * pow(dist / rho, 2.0);

        // Apply the force of gravity exerted by the origin.
        applyForce(origin, force);
    }

    /**
     * Returns the Vivaldi distance to `other` in estimated round-trip time.
     *
     * To include adjustments in a hybrid coordinate system, see Node.
     */
    double distanceTo(const ref Coordinate other) const pure nothrow @safe @nogc {
        double[dims] diff = vector[] - other.vector[];
        return magnitude(diff) + height + other.height;
    }

    invariant {
        ///
        static bool valid(const double d) pure nothrow @safe @nogc {
            import std.math : isInfinity, isNaN;
            return !isInfinity(d) && !isNaN(d);
        }

        foreach (i; vector) {
            assert(valid(i));
        }

        assert(valid(error));
        assert(valid(height));
    }

    /**
     * `vector` is the Euclidean component of the coordinate which
     * represents the distance from the origin in the Internet core in
     * seconds.
     */
    double[dims] vector = 0.0;

    /**
     * `height` is the non-Euclidean component of the coordinate,
     * which represents the distance along an access link to the
     * Internet core in seconds.
     */
    double height = minHeight;

    /**
     * `error` is a unitless measure of confidence that this
     * Coordinate represents the true distance from the origin.
     */
    double error = maxError;

    /**
     * Applies a `force` in seconds against this coordinate from the
     * direction of `other`.
     *
     * If force is a positive value, this coordinate will be pushed
     * away from other. If negative, this coordinate will be pulled
     * closer to other.
     */
    private void applyForce(const ref Coordinate other, const double force)
         nothrow @safe @nogc {
        import std.algorithm : max;

        double[dims] unit;
        const mag = unitvector(vector, other.vector, unit);

        unit[] *= force;
        vector[] += unit[];

        if (mag > double.min_normal) {
            height = max((height + other.height) * force / mag + height, minHeight);
        }
    }

}

@("defaults")
nothrow @safe @nogc unittest {
    auto coord = Coordinate!4();

    assert(coord.vector == [ 0.0, 0.0, 0.0, 0.0 ]);
    assert(magnitude(coord.vector) == 0.0);
    assert(coord.error == 1.5);
    assert(coord.height == 1.0e-5);
}

@("update")
nothrow @safe @nogc unittest {
    auto c = Coordinate!4();

    assert(c.vector == [ 0.0, 0.0, 0.0, 0.0 ]);

    // Place another node above and nearby; update with a high RTT.
    auto other = Coordinate!4();
    other.vector[2] = 0.001;

    c.update(other, 0.2);

    // The coordinate should be pushed away along the correct axis.
    assert(c.vector[0] == 0.0);
    assert(c.vector[1] == 0.0);
    assert(c.vector[2] < 0.0);
    assert(c.vector[3] == 0.0);
}

@("constant factors")
unittest {
    // Vivaldi ce term
    assert(!__traits(compiles, Coordinate!(4, 1.5, 1.0e-5, 0.0 - double.epsilon)));
    assert(!__traits(compiles, Coordinate!(4, 1.5, 1.0e-5, 1.0 + double.epsilon)));
    assert(!__traits(compiles, Coordinate!(4, 1.5, 1.0e-5, double.nan)));

    // Vivaldi cc term
    assert(!__traits(compiles, Coordinate!(4, 1.5, 1.0e-5, 0.25, 0.0 - double.epsilon)));
    assert(!__traits(compiles, Coordinate!(4, 1.5, 1.0e-5, 0.25, 1.0 + double.epsilon)));
    assert(!__traits(compiles, Coordinate!(4, 1.5, 1.0e-5, 0.25, double.nan)));

    // Gravitational constant
    assert(!__traits(compiles, Coordinate!(4, 1.5, 1.0e-5, 0.25, 0.25, 0.0)));
    assert(!__traits(compiles, Coordinate!(4, 1.5, 1.0e-5, 0.25, 0.25, 0.0 - double.epsilon)));
    assert(!__traits(compiles, Coordinate!(4, 1.5, 1.0e-5, 0.25, 0.25, double.nan)));
    assert(!__traits(compiles, Coordinate!(4, 1.5, 1.0e-5, 0.25, 0.25, double.infinity)));
}

@("zero rtt")
nothrow @safe @nogc unittest {
    auto c = Coordinate!4();
    auto other = Coordinate!4();

    c.update(other, 0);

    // A zero RTT pushes away regardless.
    assert(c.distanceTo(other) > 0);

    // The error term should not blow out.
    assert(c.error == 1.5);
}

@("finite rtt")
unittest {
    import core.exception : AssertError;
    import std.exception;

    auto a = Coordinate!4();
    auto b = Coordinate!4();

    assertThrown!AssertError(a.update(b, double.infinity));
    assertThrown!AssertError(a.update(b, -double.infinity));
    assertThrown!AssertError(a.update(b, double.nan));
}

@("zero error")
unittest {
    auto c = Coordinate!4();
    auto other = Coordinate!4();

    // This test the invariant that total error does not
    // divide-by-zero and cause the coordinate to be invalid.
    c.error = 0;
    other.error = 0;

    c.update(other, 0.1);

    assert(c.error == 0);
    assert(c.distanceTo(other) > 0);
}

@("distanceTo")
nothrow @safe @nogc unittest {
    version (DigitalMars) {
        import std.math : isClose;
    } else version (LDC) {
        import std.math : approxEqual;
        alias isClose = approxEqual;
    }

    auto c1 = Coordinate!(3, 1.5, 0)();
    c1.vector = [ -0.5, 1.3, 2.4 ];

    auto c2 = Coordinate!(3, 1.5, 0)();
    c2.vector = [ 1.2, -2.3, 3.4 ];

    assert(c1.distanceTo(c1) == 0);
    assert(c1.distanceTo(c2) == c2.distanceTo(c1));
    assert(isClose(c1.distanceTo(c2), 4.104875150354758));

    c1.height = 0.7;
    c2.height = 0.1;
    assert(isClose(c1.distanceTo(c2), 4.104875150354758 + 0.8));
}

@("applyForce zero height")
nothrow @safe @nogc unittest {
    version (DigitalMars) {
        import std.math : isClose;
    } else version (LDC) {
        import std.math : approxEqual;
        alias isClose = approxEqual;
    }

    auto origin = Coordinate!(3, 1.5, 0)();

    auto above = Coordinate!(3, 1.5, 0)();
    above.vector = [ 0.0, 0.0, 2.9 ];

    auto c = origin;
    c.applyForce(above, 5.3);
    assert(c.vector == [ 0.0, 0.0, -5.3 ]);

    auto right = Coordinate!(3, 1.5, 0)();
    right.vector = [ 3.4, 0.0, -5.3 ];
    c.applyForce(right, 2.0);
    assert(c.vector == [ -2.0, 0.0, -5.3 ]);

    c = origin;
    c.applyForce(origin, 1.0);
    assert(isClose(origin.distanceTo(c), 1.0));
}

@("applyForce default height")
@safe unittest {
    import std.format;

    version (DigitalMars) {
        import std.math : isClose;
    } else version (LDC) {
        import std.math : approxEqual;
        alias isClose = approxEqual;
    }

    auto origin = Coordinate!3();
    auto c = origin;

    auto above = Coordinate!3();
    above.vector = [ 0.0, 0.0, 2.9 ];
    above.height = 0.0;

    c.applyForce(above, 5.3);
    assert(c.vector == [ 0.0, 0.0, -5.3 ]);
    assert(isClose(c.height, 1.0e-5 + 5.3 * 1.0e-5 / 2.9));

    c = origin;
    c.applyForce(above, -5.3);
    assert(c.vector == [ 0.0, 0.0, 5.3 ]);
    assert(isClose(c.height, 1.0e-5));
}

// FIXME: scale to prevent overflow
private double magnitude(size_t D)(const double[D] vec) pure nothrow @safe @nogc
     if (D > 0)
{
    import std.algorithm : map, sum;

    version (DigitalMars) {
        import std.math.algebraic : sqrt;
    } else version (LDC) {
        import std.math : sqrt;
    }

    return sqrt(sum(vec[].map!(a => a * a)));
}

@("magnitude")
nothrow @nogc @safe unittest {
    version (DigitalMars) {
        import std.math : isClose;
    } else version (LDC) {
        import std.math : approxEqual;
        alias isClose = approxEqual;
    }

    assert(magnitude([ 0.0, 0.0, 0.0, 0.0 ]) == 0.0);
    assert(isClose(magnitude([ 1.0, -2.0, 3.0 ]), 3.7416573867739413));
    assert(!__traits(compiles, magnitude([])));
}

/**
 * Returns a unit vector pointing at `dest` from `src` in `ret` and
 * the distance between the two inputs.
 */
private double unitvector(size_t D)(const double[D] dest,
                          const double[D] src,
                          ref double[D] ret) nothrow @safe @nogc
     if (D > 0)
{
    import std.random : uniform01;

    double mag;

    ret[] = dest[] - src[];

    mag = magnitude(ret);
    // Push if the two vectors aren't too close.
    if (mag > double.min_normal) {
        ret[] *= 1.0 / mag;
        return mag;
    }

    // Push in a random direction if they _are_ close.
    //
    // cf. "Two nodes occupying the same location will have a spring
    // pushing them away from each other in some arbitrary direction."
    foreach (ref n; ret) {
        n = uniform01() - 0.5;
    }

    mag = magnitude(ret);
    if (mag > double.min_normal) {
        ret[] *= 1.0 / mag;
        return 0.0;
    }

    // Well, that didn't work out... push along the first dimension;
    // it is the only dimension all coordinates have.
    ret[] = 0.0;
    ret[0] = 1.0;
    return 0.0;
}

@("unitvector")
nothrow @safe @nogc unittest {
    version (DigitalMars) {
        import std.math : isClose;
    } else version (LDC) {
        import std.math : approxEqual;
        alias isClose = approxEqual;
    }

    assert(!__traits(compiles, unitvector([])));

    double[3] a = [ 1.0, 2.0, 3.0 ];
    double[3] b = [ 0.5, 0.6, 0.7 ];

    double[3] result;

    {
        auto mag = unitvector(a, b, result);
        assert(isClose(magnitude(result), 1.0));

        double[3] diff = a[] - b[];
        assert(isClose(mag, magnitude(diff)));

        double[3] expected = [0.18257418583505536,
                              0.511207720338155,
                              0.8398412548412546];

        foreach (i, v; result) {
            assert(isClose(v, expected[i]));
        }
    }

    auto mag = unitvector(a, a, result);
    assert(isClose(magnitude(result), 1.0));
    assert(isClose(mag, 0.0));
}
