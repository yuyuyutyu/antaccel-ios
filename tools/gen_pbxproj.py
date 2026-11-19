# -*- coding: utf-8 -*-
import os, io

ROOT = r"C:\ipa workplace\out\ios"
PROJ_DIR = os.path.join(ROOT, "AntiAccel.xcodeproj")
os.makedirs(PROJ_DIR, exist_ok=True)

def oid(prefix, n):
    s = prefix + format(n, "022d")
    assert len(s) == 24, s
    return s

PROJECT      = oid("AA", 1)
MAIN_GROUP   = oid("AA", 2)
PRODUCTS_GRP = oid("AA", 3)
APP_GROUP    = oid("AA", 4)
SRC_GROUP    = oid("AA", 5)
RES_GROUP    = oid("AA", 6)
TARGET       = oid("AA", 7)
SRC_PHASE    = oid("AA", 8)
FRM_PHASE    = oid("AA", 9)
RES_PHASE    = oid("AA", 10)
PROJ_CFGLIST = oid("AA", 11)
TGT_CFGLIST  = oid("AA", 12)
PROJ_DEBUG   = oid("AA", 13)
PROJ_RELEASE = oid("AA", 14)
TGT_DEBUG    = oid("AA", 15)
TGT_RELEASE  = oid("AA", 16)
PRODUCT_REF  = oid("AA", 17)

swift_files = [
    "AppDelegate.swift",
    "SceneDelegate.swift",
    "RootTabBarController.swift",
    "AppConfig.swift",
    "Bridge.swift",
    "HomeViewController.swift",
    "BrowserViewController.swift",
    "NavWebViewController.swift",
    "ProfileViewController.swift",
]
res_files = [
    ("index.html", "text.html"),
    ("nav_default_home.json", "text.json"),
    ("NativeObject.js", "sourcecode.javascript"),
    ("client-bff-rsa-prod2.public.pem", "text"),
]

src_refs, src_bfs, res_refs, res_bfs = [], [], [], []
lines = []
w = lines.append

w("// !$*UTF8*$!")
w("{")
w("\tarchiveVersion = 1;")
w("\tclasses = {")
w("\t};")
w("\tobjectVersion = 52;")
w("\tobjects = {")
w("")

# ---- PBXBuildFile ----
w("/* Begin PBXBuildFile section */")
for i, name in enumerate(swift_files):
    fr = oid("F1", i + 1); bf = oid("B1", i + 1)
    src_refs.append((name, fr)); src_bfs.append((name, fr, bf))
    w("\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };" % (bf, name, fr, name))
for i, (name, _t) in enumerate(res_files):
    fr = oid("F2", i + 1); bf = oid("B2", i + 1)
    res_refs.append((name, fr)); res_bfs.append((name, fr, bf))
    w("\t\t%s /* %s in Resources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };" % (bf, name, fr, name))
ASSETS_REF = oid("F2", 11); ASSETS_BF = oid("B2", 11)
SB_REF = oid("F2", 12); SB_BF = oid("B2", 12)
INFO_REF = oid("F2", 13)
w("\t\t%s /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = %s /* Assets.xcassets */; };" % (ASSETS_BF, ASSETS_REF))
w("\t\t%s /* LaunchScreen.storyboard in Resources */ = {isa = PBXBuildFile; fileRef = %s /* LaunchScreen.storyboard */; };" % (SB_BF, SB_REF))
w("/* End PBXBuildFile section */")
w("")

# ---- PBXFileReference ----
w("/* Begin PBXFileReference section */")
for name, fr in src_refs:
    w("\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = %s; sourceTree = \"<group>\"; };" % (fr, name, name))
for name, fr in res_refs:
    t = dict(res_files)[name]
    w("\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = %s; path = %s; sourceTree = \"<group>\"; };" % (fr, name, t, name))
w("\t\t%s /* Assets.xcassets */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = \"<group>\"; };" % ASSETS_REF)
w("\t\t%s /* LaunchScreen.storyboard */ = {isa = PBXFileReference; lastKnownFileType = file.storyboard; path = LaunchScreen.storyboard; sourceTree = \"<group>\"; };" % SB_REF)
w("\t\t%s /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; };" % INFO_REF)
w("\t\t%s /* AntiAccel.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = AntiAccel.app; sourceTree = BUILT_PRODUCTS_DIR; };" % PRODUCT_REF)
w("/* End PBXFileReference section */")
w("")

# ---- PBXFrameworksBuildPhase ----
w("/* Begin PBXFrameworksBuildPhase section */")
w("\t\t%s /* Frameworks */ = {" % FRM_PHASE)
w("\t\t\tisa = PBXFrameworksBuildPhase;")
w("\t\t\tbuildActionMask = 2147483647;")
w("\t\t\tfiles = (")
w("\t\t\t);")
w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
w("\t\t};")
w("/* End PBXFrameworksBuildPhase section */")
w("")

# ---- PBXGroup ----
w("/* Begin PBXGroup section */")
w("\t\t%s = {" % MAIN_GROUP)
w("\t\t\tisa = PBXGroup;")
w("\t\t\tchildren = (")
w("\t\t\t\t%s /* AntiAccel */," % APP_GROUP)
w("\t\t\t\t%s /* Products */," % PRODUCTS_GRP)
w("\t\t\t);")
w("\t\t\tsourceTree = \"<group>\";")
w("\t\t};")
w("\t\t%s /* AntiAccel */ = {" % APP_GROUP)
w("\t\t\tisa = PBXGroup;")
w("\t\t\tchildren = (")
w("\t\t\t\t%s /* Sources */," % SRC_GROUP)
w("\t\t\t\t%s /* Resources */," % RES_GROUP)
w("\t\t\t\t%s /* Assets.xcassets */," % ASSETS_REF)
w("\t\t\t\t%s /* LaunchScreen.storyboard */," % SB_REF)
w("\t\t\t\t%s /* Info.plist */," % INFO_REF)
w("\t\t\t);")
w("\t\t\tpath = AntiAccel;")
w("\t\t\tsourceTree = \"<group>\";")
w("\t\t};")
w("\t\t%s /* Sources */ = {" % SRC_GROUP)
w("\t\t\tisa = PBXGroup;")
w("\t\t\tchildren = (")
for name, fr in src_refs:
    w("\t\t\t\t%s /* %s */," % (fr, name))
w("\t\t\t);")
w("\t\t\tpath = Sources;")
w("\t\t\tsourceTree = \"<group>\";")
w("\t\t};")
w("\t\t%s /* Resources */ = {" % RES_GROUP)
w("\t\t\tisa = PBXGroup;")
w("\t\t\tchildren = (")
for name, fr in res_refs:
    w("\t\t\t\t%s /* %s */," % (fr, name))
w("\t\t\t);")
w("\t\t\tpath = Resources;")
w("\t\t\tsourceTree = \"<group>\";")
w("\t\t};")
w("\t\t%s /* Products */ = {" % PRODUCTS_GRP)
w("\t\t\tisa = PBXGroup;")
w("\t\t\tchildren = (")
w("\t\t\t\t%s /* AntiAccel.app */," % PRODUCT_REF)
w("\t\t\t);")
w("\t\t\tname = Products;")
w("\t\t\tsourceTree = \"<group>\";")
w("\t\t};")
w("/* End PBXGroup section */")
w("")

# ---- PBXNativeTarget ----
w("/* Begin PBXNativeTarget section */")
w("\t\t%s /* AntiAccel */ = {" % TARGET)
w("\t\t\tisa = PBXNativeTarget;")
w("\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXNativeTarget \"AntiAccel\" */;" % TGT_CFGLIST)
w("\t\t\tbuildPhases = (")
w("\t\t\t\t%s /* Sources */," % SRC_PHASE)
w("\t\t\t\t%s /* Frameworks */," % FRM_PHASE)
w("\t\t\t\t%s /* Resources */," % RES_PHASE)
w("\t\t\t);")
w("\t\t\tbuildRules = (")
w("\t\t\t);")
w("\t\t\tdependencies = (")
w("\t\t\t);")
w("\t\t\tname = AntiAccel;")
w("\t\t\tproductName = AntiAccel;")
w("\t\t\tproductReference = %s /* AntiAccel.app */;" % PRODUCT_REF)
w("\t\t\tproductType = \"com.apple.product-type.application\";")
w("\t\t};")
w("/* End PBXNativeTarget section */")
w("")

# ---- PBXProject ----
w("/* Begin PBXProject section */")
w("\t\t%s /* Project object */ = {" % PROJECT)
w("\t\t\tisa = PBXProject;")
w("\t\t\tattributes = {")
w("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
w("\t\t\t\tLastUpgradeCheck = 1500;")
w("\t\t\t\tTargetAttributes = {")
w("\t\t\t\t\t%s = {" % TARGET)
w("\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;")
w("\t\t\t\t\t};")
w("\t\t\t\t};")
w("\t\t\t};")
w("\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXProject \"AntiAccel\" */;" % PROJ_CFGLIST)
w("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
w("\t\t\tdevelopmentRegion = en;")
w("\t\t\thasScannedForEncodings = 0;")
w("\t\t\tknownRegions = (")
w("\t\t\t\ten,")
w("\t\t\t\tBase,")
w("\t\t\t);")
w("\t\t\tmainGroup = %s;" % MAIN_GROUP)
w("\t\t\tproductRefGroup = %s /* Products */;" % PRODUCTS_GRP)
w("\t\t\tprojectDirPath = \"\";")
w("\t\t\tprojectRoot = \"\";")
w("\t\t\ttargets = (")
w("\t\t\t\t%s /* AntiAccel */," % TARGET)
w("\t\t\t);")
w("\t\t};")
w("/* End PBXProject section */")
w("")

# ---- PBXResourcesBuildPhase ----
w("/* Begin PBXResourcesBuildPhase section */")
w("\t\t%s /* Resources */ = {" % RES_PHASE)
w("\t\t\tisa = PBXResourcesBuildPhase;")
w("\t\t\tbuildActionMask = 2147483647;")
w("\t\t\tfiles = (")
for name, fr, bf in res_bfs:
    w("\t\t\t\t%s /* %s in Resources */," % (bf, name))
w("\t\t\t\t%s /* Assets.xcassets in Resources */," % ASSETS_BF)
w("\t\t\t\t%s /* LaunchScreen.storyboard in Resources */," % SB_BF)
w("\t\t\t);")
w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
w("\t\t};")
w("/* End PBXResourcesBuildPhase section */")
w("")

# ---- PBXSourcesBuildPhase ----
w("/* Begin PBXSourcesBuildPhase section */")
w("\t\t%s /* Sources */ = {" % SRC_PHASE)
w("\t\t\tisa = PBXSourcesBuildPhase;")
w("\t\t\tbuildActionMask = 2147483647;")
w("\t\t\tfiles = (")
for name, fr, bf in src_bfs:
    w("\t\t\t\t%s /* %s in Sources */," % (bf, name))
w("\t\t\t);")
w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
w("\t\t};")
w("/* End PBXSourcesBuildPhase section */")
w("")

proj_common = [
    ("ALWAYS_SEARCH_USER_PATHS", "NO"),
    ("CLANG_ANALYZER_NONNULL", "YES"),
    ("CLANG_ENABLE_MODULES", "YES"),
    ("CLANG_ENABLE_OBJC_ARC", "YES"),
    ("CLANG_WARN_BOOL_CONVERSION", "YES"),
    ("CLANG_WARN_DOCUMENTATION_COMMENTS", "YES"),
    ("CLANG_WARN_EMPTY_BODY", "YES"),
    ("CLANG_WARN_ENUM_CONVERSION", "YES"),
    ("CLANG_WARN_UNREACHABLE_CODE", "YES"),
    ("COPY_PHASE_STRIP", "NO"),
    ("ENABLE_STRICT_OBJC_MSGSEND", "YES"),
    ("GCC_C_LANGUAGE_STANDARD", "gnu11"),
    ("GCC_NO_COMMON_BLOCKS", "YES"),
    ("GCC_WARN_UNDECLARED_SELECTOR", "YES"),
    ("GCC_WARN_UNINITIALIZED_AUTOS", "YES"),
    ("GCC_WARN_UNUSED_FUNCTION", "YES"),
    ("GCC_WARN_UNUSED_VARIABLE", "YES"),
    ("IPHONEOS_DEPLOYMENT_TARGET", "13.0"),
    ("SDKROOT", "iphoneos"),
    ("SWIFT_VERSION", "5.0"),
]

proj_debug = proj_common + [
    ("DEBUG_INFORMATION_FORMAT", "dwarf"),
    ("ENABLE_TESTABILITY", "YES"),
    ("GCC_DYNAMIC_NO_PIC", "NO"),
    ("GCC_OPTIMIZATION_LEVEL", "0"),
    ("GCC_PREPROCESSOR_DEFINITIONS", "(\n\t\t\t\t\t\"DEBUG=1\",\n\t\t\t\t\t\"$(inherited)\",\n\t\t\t\t)"),
    ("MTL_ENABLE_DEBUG_INFO", "INCLUDE_SOURCE"),
    ("ONLY_ACTIVE_ARCH", "YES"),
    ("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "DEBUG"),
    ("SWIFT_OPTIMIZATION_LEVEL", "\"-Onone\""),
]

proj_release = proj_common + [
    ("DEBUG_INFORMATION_FORMAT", "\"dwarf-with-dsym\""),
    ("ENABLE_NS_ASSERTIONS", "NO"),
    ("GCC_OPTIMIZATION_LEVEL", "s"),
    ("MTL_ENABLE_DEBUG_INFO", "NO"),
    ("SWIFT_COMPILATION_MODE", "wholemodule"),
    ("SWIFT_OPTIMIZATION_LEVEL", "\"-O\""),
    ("VALIDATE_PRODUCT", "YES"),
]

tgt_common = [
    ("ASSETCATALOG_COMPILER_APPICON_NAME", "AppIcon"),
    ("ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME", "AccentColor"),
    ("CODE_SIGN_STYLE", "Automatic"),
    ("CURRENT_PROJECT_VERSION", "4"),
    ("GENERATE_INFOPLIST_FILE", "NO"),
    ("INFOPLIST_FILE", "AntiAccel/Info.plist"),
    ("LD_RUNPATH_SEARCH_PATHS", "(\n\t\t\t\t\t\"$(inherited)\",\n\t\t\t\t\t\"@executable_path/Frameworks\",\n\t\t\t\t)"),
    ("MARKETING_VERSION", "1.0.5"),
    ("PRODUCT_BUNDLE_IDENTIFIER", "com.arknet.shell"),
    ("PRODUCT_MODULE_NAME", "AntiAccel"),
    ("PRODUCT_NAME", "\"$(TARGET_NAME)\""),
    ("SWIFT_EMIT_LOC_STRINGS", "YES"),
    ("TARGETED_DEVICE_FAMILY", "\"1,2\""),
]

def emit_config(cid, name, settings):
    w("\t\t%s /* %s */ = {" % (cid, name))
    w("\t\t\tisa = XCBuildConfiguration;")
    w("\t\t\tbuildSettings = {")
    for key, value in settings:
        if value.startswith("("):
            w("\t\t\t\t%s = %s;" % (key, value))
        else:
            w("\t\t\t\t%s = %s;" % (key, value))
    w("\t\t\t};")
    w("\t\t\tname = %s;" % name)
    w("\t\t};")

w("/* Begin XCBuildConfiguration section */")
emit_config(PROJ_DEBUG, "Debug", proj_debug)
emit_config(PROJ_RELEASE, "Release", proj_release)
emit_config(TGT_DEBUG, "Debug", tgt_common)
emit_config(TGT_RELEASE, "Release", tgt_common)
w("/* End XCBuildConfiguration section */")
w("")

w("/* Begin XCConfigurationList section */")
w("\t\t%s /* Build configuration list for PBXProject \"AntiAccel\" */ = {" % PROJ_CFGLIST)
w("\t\t\tisa = XCConfigurationList;")
w("\t\t\tbuildConfigurations = (")
w("\t\t\t\t%s /* Debug */," % PROJ_DEBUG)
w("\t\t\t\t%s /* Release */," % PROJ_RELEASE)
w("\t\t\t);")
w("\t\t\tdefaultConfigurationIsVisible = 0;")
w("\t\t\tdefaultConfigurationName = Release;")
w("\t\t};")
w("\t\t%s /* Build configuration list for PBXNativeTarget \"AntiAccel\" */ = {" % TGT_CFGLIST)
w("\t\t\tisa = XCConfigurationList;")
w("\t\t\tbuildConfigurations = (")
w("\t\t\t\t%s /* Debug */," % TGT_DEBUG)
w("\t\t\t\t%s /* Release */," % TGT_RELEASE)
w("\t\t\t);")
w("\t\t\tdefaultConfigurationIsVisible = 0;")
w("\t\t\tdefaultConfigurationName = Release;")
w("\t\t};")
w("/* End XCConfigurationList section */")
w("\t};")
w("\trootObject = %s /* Project object */;" % PROJECT)
w("}")

out = "\n".join(lines) + "\n"
open(os.path.join(PROJ_DIR, "project.pbxproj"), "w", encoding="utf-8", newline="\n").write(out)
print("written", len(out), "bytes")
print("braces:", out.count("{"), out.count("}"), "parens:", out.count("("), out.count(")"))
