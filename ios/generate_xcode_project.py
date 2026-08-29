#!/usr/bin/env python3
"""Generate PopupApp.xcodeproj for the SwiftUI sources under BakpakApp/.

Embeds the Supabase Swift package and Config/SupabaseProject.xcconfig so ./run-simulator.sh and xcodebuild work without re-adding SPM in Xcode.
"""
import hashlib
import os


def gid(seed: str) -> str:
    """Stable 24-char hex IDs so the project file does not churn on every run."""
    return hashlib.sha256(seed.encode()).hexdigest()[:24].upper()


def main() -> None:
    ios_root = os.path.dirname(os.path.abspath(__file__))
    popup = os.path.join(ios_root, "BakpakApp")

    swift_files = []
    resource_files = []
    for root, dirs, files in os.walk(popup):
        dirs.sort()
        dirs[:] = [d for d in dirs if d != "Assets.xcassets"]
        for f in sorted(files):
            if f.endswith(".swift"):
                rel = os.path.relpath(os.path.join(root, f), ios_root)
                swift_files.append(rel.replace("\\", "/"))
            if f.endswith(".ttf") or f.endswith(".otf") or f.endswith(".png") or f.endswith(".jpg") or f.endswith(".jpeg"):
                rel = os.path.relpath(os.path.join(root, f), ios_root)
                resource_files.append(rel.replace("\\", "/"))
    swift_files.sort()
    resource_files.sort()

    project_id = gid("popup:project")
    target_id = gid("popup:target:PopupApp")
    main_group = gid("popup:group:main")
    products_group = gid("popup:group:products")
    app_group = gid("popup:group:PopupApp")
    core_group = gid("popup:group:Core")
    views_group = gid("popup:group:Views")
    auth_group = gid("popup:group:Auth")
    resources_group = gid("popup:group:Resources")
    fonts_group = gid("popup:group:Fonts")
    images_group = gid("popup:group:Images")
    sources_phase = gid("popup:phase:sources")
    resources_phase = gid("popup:phase:resources")
    frameworks_phase = gid("popup:phase:frameworks")
    project_config_list = gid("popup:cfglist:project")
    target_config_list = gid("popup:cfglist:target")
    product_ref = gid("popup:product:PopupApp.app")
    infoplist_ref = gid("popup:fileref:Info.plist")
    debug_project = gid("popup:xcconfig:project:Debug")
    release_project = gid("popup:xcconfig:project:Release")
    debug_target = gid("popup:xcconfig:target:Debug")
    release_target = gid("popup:xcconfig:target:Release")
    config_group = gid("popup:group:Config")
    xcconfig_ref = gid("popup:fileref:SupabaseProject.xcconfig")
    assets_ref = gid("popup:fileref:Assets.xcassets")
    assets_build = gid("popup:build:Assets.xcassets")
    spa_remote = gid("popup:swiftpkg:supabase-remote")
    spa_product = gid("popup:swiftpkg:supabase-product")
    spa_build = gid("popup:swiftpkg:supabase-buildfile")
    square_remote = gid("popup:swiftpkg:square-remote")
    square_product = gid("popup:swiftpkg:square-product")
    square_build = gid("popup:swiftpkg:square-buildfile")
    square_mock_product = gid("popup:swiftpkg:square-mock-product")
    square_mock_build = gid("popup:swiftpkg:square-mock-buildfile")
    square_iap_remote = gid("popup:swiftpkg:square-iap-remote")
    square_iap_product = gid("popup:swiftpkg:square-iap-product")
    square_iap_build = gid("popup:swiftpkg:square-iap-buildfile")
    debug_entitlements_ref = gid("popup:fileref:PopupApp.Debug.entitlements")
    release_entitlements_ref = gid("popup:fileref:PopupApp.entitlements")

    # path -> (file_ref_id, build_file_id)
    refs: dict[str, tuple[str, str]] = {
        p: (gid(f"popup:fileref:{p}"), gid(f"popup:build:{p}")) for p in swift_files
    }
    resource_refs: dict[str, tuple[str, str]] = {
        p: (gid(f"popup:fileref:{p}"), gid(f"popup:build:{p}")) for p in resource_files
    }

    def ref_block(path: str) -> str:
        rid, _ = refs[path]
        name = os.path.basename(path)
        return (
            f"\t\t{rid} /* {name} */ = {{"
            f"isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
            f"path = {repr(name)}; sourceTree = \"<group>\"; }};\n"
        )

    build_file_lines = []
    for path in swift_files:
        rid, bid = refs[path]
        name = os.path.basename(path)
        build_file_lines.append(
            f"\t\t{bid} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {rid} /* {name} */; }};"
        )
    for path in resource_files:
        rid, bid = resource_refs[path]
        name = os.path.basename(path)
        build_file_lines.append(
            f"\t\t{bid} /* {name} in Resources */ = {{isa = PBXBuildFile; fileRef = {rid} /* {name} */; }};"
        )

    root_swifts = [p for p in swift_files if os.path.dirname(p) == "BakpakApp"]
    core_swifts = [p for p in swift_files if os.path.dirname(p) == "BakpakApp/Core"]
    views_root_swifts = [p for p in swift_files if os.path.dirname(p) == "BakpakApp/Views"]
    auth_swifts = [p for p in swift_files if os.path.dirname(p) == "BakpakApp/Views/Auth"]
    font_resources = [p for p in resource_files if os.path.dirname(p) == "BakpakApp/Resources/Fonts"]
    image_resources = [p for p in resource_files if os.path.dirname(p) == "BakpakApp/Resources/Images"]

    def group_child_lines(paths: list[str]) -> str:
        lines = []
        for p in paths:
            rid, _ = refs[p]
            nm = os.path.basename(p)
            lines.append(f"\t\t\t\t{rid} /* {nm} */,")
        return "\n".join(lines)

    source_phase_lines = []
    for p in swift_files:
        _, bid = refs[p]
        nm = os.path.basename(p)
        source_phase_lines.append(f"\t\t\t\t{bid} /* {nm} in Sources */,")
    source_phase_block = "\n".join(source_phase_lines)
    resources_phase_lines = []
    for p in resource_files:
        _, bid = resource_refs[p]
        nm = os.path.basename(p)
        resources_phase_lines.append(f"\t\t\t\t{bid} /* {nm} in Resources */,")
    resources_phase_block = "\n".join(resources_phase_lines)

    pbx = f'''// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{

/* Begin PBXBuildFile section */
{chr(10).join(build_file_lines)}
\t\t{assets_build} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {assets_ref} /* Assets.xcassets */; }};
\t\t{spa_build} /* Supabase in Frameworks */ = {{isa = PBXBuildFile; productRef = {spa_product} /* Supabase */; }};
\t\t{square_build} /* SquareMobilePaymentsSDK in Frameworks */ = {{isa = PBXBuildFile; productRef = {square_product} /* SquareMobilePaymentsSDK */; }};
\t\t{square_mock_build} /* MockReaderUI in Frameworks */ = {{isa = PBXBuildFile; productRef = {square_mock_product} /* MockReaderUI */; }};
\t\t{square_iap_build} /* SquareInAppPaymentsSDK in Frameworks */ = {{isa = PBXBuildFile; productRef = {square_iap_product} /* SquareInAppPaymentsSDK */; }};
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
\t\t{product_ref} /* PopupApp.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = PopupApp.app; sourceTree = BUILT_PRODUCTS_DIR; }};
\t\t{infoplist_ref} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};
\t\t{debug_entitlements_ref} /* PopupApp.Debug.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = PopupApp.Debug.entitlements; sourceTree = "<group>"; }};
\t\t{release_entitlements_ref} /* PopupApp.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = PopupApp.entitlements; sourceTree = "<group>"; }};
\t\t{xcconfig_ref} /* SupabaseProject.xcconfig */ = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = SupabaseProject.xcconfig; sourceTree = "<group>"; }};
\t\t{assets_ref} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; }};
{"".join(ref_block(p) for p in swift_files)}{"".join(
        f"\t\t{resource_refs[p][0]} /* {os.path.basename(p)} */ = "
        "{isa = PBXFileReference; lastKnownFileType = file; "
        f"path = {repr(os.path.basename(p))}; sourceTree = \"<group>\"; }};\n"
        for p in resource_files
    )}/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{frameworks_phase} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{spa_build} /* Supabase in Frameworks */,
\t\t\t\t{square_build} /* SquareMobilePaymentsSDK in Frameworks */,
\t\t\t\t{square_mock_build} /* MockReaderUI in Frameworks */,
\t\t\t\t{square_iap_build} /* SquareInAppPaymentsSDK in Frameworks */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t{main_group} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{config_group} /* Config */,
\t\t\t\t{app_group} /* PopupApp */,
\t\t\t\t{products_group} /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{config_group} /* Config */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{xcconfig_ref} /* SupabaseProject.xcconfig */,
\t\t\t);
\t\t\tpath = Config;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{products_group} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{product_ref} /* PopupApp.app */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{app_group} /* PopupApp */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{infoplist_ref} /* Info.plist */,
\t\t\t\t{debug_entitlements_ref} /* PopupApp.Debug.entitlements */,
\t\t\t\t{release_entitlements_ref} /* PopupApp.entitlements */,
\t\t\t\t{assets_ref} /* Assets.xcassets */,
{group_child_lines(root_swifts)}
\t\t\t\t{core_group} /* Core */,
\t\t\t\t{views_group} /* Views */,
\t\t\t\t{resources_group} /* Resources */,
\t\t\t);
\t\t\tpath = BakpakApp;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{core_group} /* Core */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{group_child_lines(core_swifts)}
\t\t\t);
\t\t\tpath = Core;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{views_group} /* Views */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{group_child_lines(views_root_swifts)}
\t\t\t\t{auth_group} /* Auth */,
\t\t\t);
\t\t\tpath = Views;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{auth_group} /* Auth */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{group_child_lines(auth_swifts)}
\t\t\t);
\t\t\tpath = Auth;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{resources_group} /* Resources */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{fonts_group} /* Fonts */,
\t\t\t\t{images_group} /* Images */,
\t\t\t);
\t\t\tpath = Resources;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{fonts_group} /* Fonts */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{"\n".join(f"\t\t\t\t{resource_refs[p][0]} /* {os.path.basename(p)} */," for p in font_resources)}
\t\t\t);
\t\t\tpath = Fonts;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{images_group} /* Images */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{"\n".join(f"\t\t\t\t{resource_refs[p][0]} /* {os.path.basename(p)} */," for p in image_resources)}
\t\t\t);
\t\t\tpath = Images;
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{target_id} /* PopupApp */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {target_config_list} /* Build configuration list for PBXNativeTarget "PopupApp" */;
\t\t\tbuildPhases = (
\t\t\t\t{sources_phase} /* Sources */,
\t\t\t\t{resources_phase} /* Resources */,
\t\t\t\t{frameworks_phase} /* Frameworks */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tpackageProductDependencies = (
\t\t\t\t{spa_product} /* Supabase */,
\t\t\t\t{square_product} /* SquareMobilePaymentsSDK */,
\t\t\t\t{square_mock_product} /* MockReaderUI */,
\t\t\t\t{square_iap_product} /* SquareInAppPaymentsSDK */,
\t\t\t);
\t\t\tname = PopupApp;
\t\t\tproductName = PopupApp;
\t\t\tproductReference = {product_ref} /* PopupApp.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{project_id} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1500;
\t\t\t\tLastUpgradeCheck = 1500;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{target_id} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {project_config_list} /* Build configuration list for PBXProject "PopupApp" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {main_group};
\t\t\tpackageReferences = (
\t\t\t\t{spa_remote} /* XCRemoteSwiftPackageReference "supabase-swift" */,
\t\t\t\t{square_remote} /* XCRemoteSwiftPackageReference "mobile-payments-sdk-ios" */,
\t\t\t\t{square_iap_remote} /* XCRemoteSwiftPackageReference "in-app-payments-ios" */,
\t\t\t);
\t\t\tproductRefGroup = {products_group} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{target_id} /* PopupApp */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXSourcesBuildPhase section */
\t\t{sources_phase} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{source_phase_block}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin PBXResourcesBuildPhase section */
\t\t{resources_phase} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{resources_phase_block}
\t\t\t\t{assets_build} /* Assets.xcassets in Resources */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin XCRemoteSwiftPackageReference section */
\t\t{spa_remote} /* XCRemoteSwiftPackageReference "supabase-swift" */ = {{
\t\t\tisa = XCRemoteSwiftPackageReference;
\t\t\trepositoryURL = "https://github.com/supabase/supabase-swift.git";
\t\t\trequirement = {{
\t\t\t\tkind = upToNextMajorVersion;
\t\t\t\tminimumVersion = 2.0.0;
\t\t\t}};
\t\t}};
\t\t{square_remote} /* XCRemoteSwiftPackageReference "mobile-payments-sdk-ios" */ = {{
\t\t\tisa = XCRemoteSwiftPackageReference;
\t\t\trepositoryURL = "https://github.com/square/mobile-payments-sdk-ios";
\t\t\trequirement = {{
\t\t\t\tkind = upToNextMinorVersion;
\t\t\t\tminimumVersion = 2.6.0;
\t\t\t}};
\t\t}};
\t\t{square_iap_remote} /* XCRemoteSwiftPackageReference "in-app-payments-ios" */ = {{
\t\t\tisa = XCRemoteSwiftPackageReference;
\t\t\trepositoryURL = "https://github.com/square/in-app-payments-ios";
\t\t\trequirement = {{
\t\t\t\tkind = upToNextMajorVersion;
\t\t\t\tminimumVersion = 1.6.4;
\t\t\t}};
\t\t}};
/* End XCRemoteSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
\t\t{spa_product} /* Supabase */ = {{
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tpackage = {spa_remote} /* XCRemoteSwiftPackageReference "supabase-swift" */;
\t\t\tproductName = Supabase;
\t\t}};
\t\t{square_product} /* SquareMobilePaymentsSDK */ = {{
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tpackage = {square_remote} /* XCRemoteSwiftPackageReference "mobile-payments-sdk-ios" */;
\t\t\tproductName = SquareMobilePaymentsSDK;
\t\t}};
\t\t{square_mock_product} /* MockReaderUI */ = {{
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tpackage = {square_remote} /* XCRemoteSwiftPackageReference "mobile-payments-sdk-ios" */;
\t\t\tproductName = MockReaderUI;
\t\t}};
\t\t{square_iap_product} /* SquareInAppPaymentsSDK */ = {{
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tpackage = {square_iap_remote} /* XCRemoteSwiftPackageReference "in-app-payments-ios" */;
\t\t\tproductName = SquareInAppPaymentsSDK;
\t\t}};
/* End XCSwiftPackageProductDependency section */

/* Begin XCBuildConfiguration section */
\t\t{debug_project} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{release_project} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{debug_target} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbaseConfigurationReference = {xcconfig_ref} /* SupabaseProject.xcconfig */;
\t\t\tbuildSettings = {{
\t\t\t\tCODE_SIGN_ENTITLEMENTS = BakpakApp/PopupApp.Debug.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_TEAM = "";
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = BakpakApp/Info.plist;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 16.7;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.popup.app;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
\t\t\t\tSUPPORTS_MACCATALYST = NO;
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{release_target} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbaseConfigurationReference = {xcconfig_ref} /* SupabaseProject.xcconfig */;
\t\t\tbuildSettings = {{
\t\t\t\tCODE_SIGN_ENTITLEMENTS = BakpakApp/PopupApp.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_TEAM = "";
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = BakpakApp/Info.plist;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 16.7;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.popup.app;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
\t\t\t\tSUPPORTS_MACCATALYST = NO;
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t}};
\t\t\tname = Release;
\t\t}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{project_config_list} /* Build configuration list for PBXProject "PopupApp" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{debug_project} /* Debug */,
\t\t\t\t{release_project} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{target_config_list} /* Build configuration list for PBXNativeTarget "PopupApp" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{debug_target} /* Debug */,
\t\t\t\t{release_target} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */
\t}};
\trootObject = {project_id} /* Project object */;
}}
'''

    proj_dir = os.path.join(ios_root, "PopupApp.xcodeproj")
    os.makedirs(proj_dir, exist_ok=True)
    pbx_path = os.path.join(proj_dir, "project.pbxproj")
    with open(pbx_path, "w", encoding="utf-8") as f:
        f.write(pbx)

    scheme_dir = os.path.join(proj_dir, "xcshareddata", "xcschemes")
    os.makedirs(scheme_dir, exist_ok=True)
    scheme_path = os.path.join(scheme_dir, "PopupApp.xcscheme")
    scheme = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1500"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "__TARGET_ID__"
               BuildableName = "PopupApp.app"
               BlueprintName = "PopupApp"
               ReferencedContainer = "container:PopupApp.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "__TARGET_ID__"
            BuildableName = "PopupApp.app"
            BlueprintName = "PopupApp"
            ReferencedContainer = "container:PopupApp.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "__TARGET_ID__"
            BuildableName = "PopupApp.app"
            BlueprintName = "PopupApp"
            ReferencedContainer = "container:PopupApp.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
""".replace("__TARGET_ID__", target_id)
    with open(scheme_path, "w", encoding="utf-8") as f:
        f.write(scheme)

    print(f"Wrote {pbx_path}")
    print(f"Wrote {scheme_path}")


if __name__ == "__main__":
    main()
