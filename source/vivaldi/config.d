module vivaldi.config;

/**
 * A set of configuration parameters for tuning the coordinate system.
 */
struct Config {
    /**
     * Limits the error any observation may induce.
     */
    double maxError = 1.5;

    /**
     * A tuning factor which impacts the maximum impact an observation can have on a Coordinate.
     */
    double ce = 0.25;

    /// ditto
    double cc = 0.25;

    /**
     * The minimum height of any Coordinate.
     */
    double minHeight = 10.0e-6;

    /**
     * Rho controls the affect of gravity exerted by the origin to
     * control drift.  See "Network Coordinates in the Wild" by
     * Ledlie, et al. for more information.
     */
    double rho = 150.0;
}
