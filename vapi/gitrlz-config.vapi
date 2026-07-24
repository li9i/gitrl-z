/*
 * The same config.h constants as vapi/config.vapi, exposed under Gitrlz.Config
 * instead of Gitg.Config.
 *
 * The vendored subtree references Gitg.Config and must keep doing so to stay
 * close to upstream (spec NFR-5). gitrl-z's own code should not have to write
 * Gitg.Config to read its own application id and version, so it gets this
 * view of the identical C defines. Both map to the same symbols in config.h;
 * there is one set of values, not two.
 */
[CCode(cprefix = "", lower_case_cprefix = "", cheader_filename = "config.h")]
namespace Gitrlz.Config
{
	public const string APPLICATION_ID;
	public const string PROFILE;
	public const string GETTEXT_PACKAGE;
	public const string PACKAGE_NAME;
	public const string PACKAGE_VERSION;
	public const string PACKAGE_URL;
	public const string GITG_DATADIR;
	public const string GITG_LOCALEDIR;
	public const string GITG_LIBDIR;
	public const string VERSION;
	public const string PLATFORM_NAME;
}

// ex:ts=4 noet
