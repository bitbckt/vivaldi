module vivaldi.coordinate;

import vivaldi.config;

import core.time;

debug(vivaldi) {
    import std.experimental.logger : tracef;
}

// Following "Network Coordinates in the Wild" by Ledlie, et al., use
// 4 dimensions plus "height".
private static enum Dimensionality = 4;

private static enum ZeroThreshold = 1.0e-6;

private static enum SecondsToNanos = 1.0e9;

/**
 * A pre-allocated point at the origin of the coordinate system.
 */
static immutable Origin = Coordinate(defaultConfig);

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
 * The non-Euclidean component represents a "height" offset, which
 * represents the distance across an access link to the core
 * Internet. Link distance on access links is typically constrained by
 * bandwidth and congestion.
 *
 * See "Vivaldi: A Decentralized Network Coordinate System" by Dabek,
 * et al.
 */
struct Coordinate {

    /**
     * Constructs a new Coordinate at the origin.
     */
    this(Config config) pure nothrow @safe @nogc {
        error = config.maxError;
        height = config.minHeight;
    }

    @("defaults")
    unittest {
        Config cfg;
        auto coord = Coordinate(cfg);

        assert(coord.vector == [ 0.0, 0.0, 0.0, 0.0 ]);
        assert(magnitude(coord.vector) == 0.0);
        assert(coord.error == cfg.maxError);
        assert(coord.height == cfg.minHeight);
    }

    @disable this();

    @("void initialization")
    unittest {
        import std.conv : emplace;

        Coordinate coord = void;
        static assert(!__traits(compiles, emplace(&coord)));
    }

    /**
     * Given a round-trip time observation for another node at
     * `other`, updates the estimated position of this Coordinate.
     */
    void update(const Config* cfg, const Coordinate* other, const Duration rtt)
         nothrow @safe @nogc {

        import std.math : abs, pow;

        double dist = distanceTo(other).total!"nsecs";
        double nanos = rtt.total!"nsecs";

        if (nanos < ZeroThreshold) {
            nanos = ZeroThreshold;
        }

        // This term is the relative error of this sample.
        const double err = abs(dist - nanos) / nanos;

        double total = error + other.error;

        if (total < ZeroThreshold) {
            total = ZeroThreshold;
        }

        // Weight is used to push in proportion to the error: large
        // error -> large force.
        const double weight = error / total;

        error = err * cfg.ce * weight + error * (1.0 - cfg.ce * weight);

        double delta = cfg.cc * weight;

        // NB. force is in seconds
        double force = delta * (nanos - dist) / SecondsToNanos;

        debug(vivaldi) {
            tracef("applying force %f from %s to %s due to RTT %s",
                   force,
                   *other,
                   this,
                   rtt);
        }

        // Apply the force exerted by the other node.
        applyForce(cfg, other, force);

        dist = Origin.distanceTo(&this).total!"seconds";
        force = -1.0 * pow(dist / cfg.rho, 2.0);

        debug(vivaldi) {
            tracef("applying force %f to %s due to gravity",
                   force,
                   this);
        }

        // Apply the force of gravity exerted by the origin.
        applyForce(cfg, &Origin, force);
    }

    @("update")
    unittest {
        Config cfg;
        Coordinate c = Coordinate(cfg);

        assert(c.vector == [ 0.0, 0.0, 0.0, 0.0 ]);

        // Place another node above and nearby; update with a high RTT.
        Coordinate other = Coordinate(cfg);
        other.vector[2] = 0.001;

        Duration rtt = msecs(2);
        c.update(&cfg, &other, rtt);

        // The coordinate should be pushed away along the correct axis.
        assert(c.vector[0] == 0.0);
        assert(c.vector[1] == 0.0);
        assert(c.vector[2] < 0.0);
        assert(c.vector[3] == 0.0);
    }

    /**
     * Returns the distance to `other` in estimated round-trip time.
     */
    Duration distanceTo(const Coordinate* other) const pure nothrow @safe @nogc {
        double[Dimensionality] diff = vector[] - other.vector[];

        // NB. height and magnitude are in seconds.
        const double dist = magnitude(diff) + height + other.height;

        return nsecs(cast(long)(dist * SecondsToNanos));
    }

    @("distanceTo")
    unittest {
        Config cfg;
        cfg.minHeight = 0;

        auto c1 = Coordinate(cfg);
        c1.vector = [ -0.5, 1.3, 2.4, 0.0 ];

        auto c2 = Coordinate(cfg);
        c2.vector = [ 1.2, -2.3, 3.4, 0.0 ];

        assert(c1.distanceTo(&c1).total!"msecs" == 0);
        assert(c1.distanceTo(&c2).total!"msecs" == c2.distanceTo(&c1).total!"msecs");
        assert(c1.distanceTo(&c2).total!"msecs" == 4104);

        c1.height = 0.7;
        c2.height = 0.1;
        assert(c1.distanceTo(&c2).total!"msecs" == 4104 + 800);
    }

private:

    invariant {
        static bool valid(double d) pure nothrow @safe @nogc {
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
    double[Dimensionality] vector = 0.0;

    /**
     * `height` is the non-Euclidean component of the coordinate,
     * which represents the distance along an access link to the
     * Internet core in seconds.
     */
    double height;

    /**
     * `error` is a unitless measure of confidence that this
     * Coordinate represents the true distance from the origin.
     */
    double error;

    /**
     * Applies a `force` in seconds against this coordinate from the
     * direction of `other`.
     */
    void applyForce(const Config* cfg, const Coordinate* other, double force) nothrow @safe @nogc {
        import std.algorithm : max;

        double[Dimensionality] unit;
        const double mag = unitvector(vector, other.vector, unit);

        vector[] += unit[] * force;

        if (mag > ZeroThreshold) {
            height = max((height + other.height) * force / mag + height, cfg.minHeight);
        }
    }

    @("applyForce")
    unittest {
        version (DigitalMars) {
            import std.math : isClose;
        } else version (LDC) {
            import std.math : approxEqual;
            alias isClose = approxEqual;
        }

        Config cfg;
        cfg.minHeight = 0;

        auto origin = Coordinate(cfg);

        auto above = Coordinate(cfg);
        above.vector = [ 0.0, 0.0, 2.9, 0.0 ];

        Coordinate c = origin;
        c.applyForce(&cfg, &above, 5.3);
        assert(c.vector == [ 0.0, 0.0, -5.3, 0.0 ]);

        auto right = Coordinate(cfg);
        right.vector = [ 3.4, 0.0, -5.3, 0.0 ];
        c.applyForce(&cfg, &right, 2.0);
        assert(c.vector == [ -2.0, 0.0, -5.3, 0.0 ]);

        c = origin;
        c.applyForce(&cfg, &origin, 1.0);
        assert(origin.distanceTo(&c) == seconds(1));

        cfg.minHeight = 10.0e-6;
        origin = Coordinate(cfg);
        c = origin;
        c.applyForce(&cfg, &above, 5.3);
        assert(c.vector == [ 0.0, 0.0, -5.3, 0.0 ]);
        assert(isClose(c.height, cfg.minHeight + 5.3 * cfg.minHeight / 2.9));

        c = origin;
        c.applyForce(&cfg, &above, -5.3);
        assert(c.vector == [ 0.0, 0.0, 5.3, 0.0 ]);
        assert(isClose(c.height, cfg.minHeight));
    }
}


// FIXME: scale to prevent overflow
private double magnitude(size_t D)(const double[D] vec) pure nothrow @safe @nogc
     if (D > 0)
{
    version (DigitalMars) {
        import std.math.algebraic : sqrt;
    } else version (LDC) {
        import std.math : sqrt;
    }

    double sum = 0.0;

    foreach (i; vec) {
        sum += i * i;
    }

    return sqrt(sum);
}

@("magnitude")
unittest {
    version (DigitalMars) {
        import std.math : isClose;
    } else version (LDC) {
        import std.math : approxEqual;
        alias isClose = approxEqual;
    }

    assert(magnitude([ 0.0, 0.0, 0.0, 0.0 ]) == 0.0);
    assert(isClose(magnitude([ 1.0, -2.0, 3.0, -4.0 ]), 5.477225575052));
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

    ret = dest[] - src[];

    mag = magnitude(ret);
    // Push if the two vectors aren't too close.
    if (mag > ZeroThreshold) {
        ret[] *= 1.0 / mag;
        return mag;
    }

    // Push in a random direction if they _are_ close.
    //
    // cf. "Two nodes occupying the same location will have a spring
    // pushing them away from each other in some arbitrary direction."
    ret[] *= uniform01() - 0.5;

    mag = magnitude(ret);
    if (mag > ZeroThreshold) {
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
unittest {
    version (DigitalMars) {
        import std.math : isClose;
    } else version (LDC) {
        import std.math : approxEqual;
        alias isClose = approxEqual;
    }

    assert(!__traits(compiles, unitvector([])));

    double[4] a = [ 1.0, 2.0, 3.0, 4.0 ];
    double[4] b = [ 0.5, 0.6, 0.7, 0.8 ];

    double[4] result;

    unitvector(a, b, result);
    assert(isClose(magnitude(result), 1.0));

    double[] expected = [0.118711610421,
                         0.332392509178,
                         0.546073407936,
                         0.759754306693];

    foreach (int i, double v; result) {
        assert(isClose(v, expected[i]));
    }

    auto mag = unitvector(a, a, result);
    assert(isClose(magnitude(result), 1.0));
    assert(isClose(mag, 0.0));
}
