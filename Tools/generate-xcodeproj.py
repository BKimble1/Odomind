#!/usr/bin/env python3
"""Regenerates Odomind.xcodeproj from what is on disk.

The project file is committed, so a clone opens in Xcode with no extra steps.
This script exists so the project can be rebuilt deterministically after files
are added or moved outside Xcode — which is exactly the situation where a
hand-edited pbxproj usually goes wrong.

    python3 Tools/generate-xcodeproj.py

Object identifiers are derived from a hash of the object's role and path, so
regenerating produces a byte-identical file and a diff shows only real changes.
"""

import hashlib
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PROJECT = ROOT / "Odomind.xcodeproj"

BUNDLE_ID = "com.idlery.odomind"
DEPLOYMENT_TARGET = "18.0"
SWIFT_VERSION = "5.0"
# A product milestone moves the marketing version with it. Build 4 is one:
# every screen was rebuilt on one surface, the app narrowed to one car at a
# time, and Parts gained a per-car specification to work from.
# Build numbers still come from App Store Connect, highest seen plus one.
MARKETING_VERSION = "1.3"
PROJECT_VERSION = "1"

APP = "Odomind"
UNIT_TESTS = "OdomindTests"
UI_TESTS = "OdomindUITests"


def oid(*parts):
    """A stable 24-character hex identifier for a pbxproj object."""
    digest = hashlib.sha256("::".join(parts).encode("utf-8")).hexdigest()
    return digest[:24].upper()


def quoted(value):
    """pbxproj string literal: bare when it is a plain token, quoted otherwise."""
    if value == "":
        return '""'
    safe = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./")
    if all(character in safe for character in value):
        return value
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def settings_block(settings, indent):
    pad = "\t" * indent
    lines = []
    for key in sorted(settings):
        value = settings[key]
        if isinstance(value, list):
            lines.append(f"{pad}{key} = (")
            for entry in value:
                lines.append(f"{pad}\t{quoted(entry)},")
            lines.append(f"{pad});")
        else:
            lines.append(f"{pad}{key} = {quoted(value)};")
    return "\n".join(lines)


def swift_files(directory):
    base = ROOT / directory
    return sorted(
        str(path.relative_to(ROOT)) for path in base.rglob("*.swift") if path.is_file()
    )


def fixture_files(directory):
    base = ROOT / directory
    if not base.exists():
        return []
    return sorted(str(path.relative_to(ROOT)) for path in base.rglob("*.json") if path.is_file())


def file_type(path):
    suffix = pathlib.Path(path).suffix
    return {
        ".swift": "sourcecode.swift",
        ".json": "text.json",
        ".plist": "text.plist.xml",
        ".xcassets": "folder.assetcatalog",
        ".md": "net.daringfireball.markdown",
        ".storekit": "text.json",
    }.get(suffix, "text")


class Tree:
    """Mirrors the folder structure so the Xcode navigator matches the disk."""

    def __init__(self, name, path=None):
        self.name = name
        self.path = path
        self.children = {}
        self.files = []

    def add(self, relative_path, full_path):
        """Files are keyed by their repository-relative path throughout."""
        parts = pathlib.Path(relative_path).parts
        node = self
        for part in parts[:-1]:
            if part not in node.children:
                node.children[part] = Tree(part, part)
            node = node.children[part]
        node.files.append(full_path)


def build_groups(tree, prefix, lines, file_refs):
    """Emits PBXGroup entries depth-first and returns this node's identifier."""
    child_ids = []
    for name in sorted(tree.children):
        child = tree.children[name]
        child_ids.append(build_groups(child, f"{prefix}/{name}", lines, file_refs))
    for path in sorted(tree.files):
        child_ids.append(file_refs[path])

    group_id = oid("group", prefix)
    body = [f"\t\t{group_id} /* {tree.name} */ = {{"]
    body.append("\t\t\tisa = PBXGroup;")
    body.append("\t\t\tchildren = (")
    for identifier in child_ids:
        body.append(f"\t\t\t\t{identifier},")
    body.append("\t\t\t);")
    if tree.path is not None:
        body.append(f"\t\t\tpath = {quoted(tree.path)};")
    else:
        body.append(f"\t\t\tname = {quoted(tree.name)};")
    body.append('\t\t\tsourceTree = "<group>";')
    body.append("\t\t};")
    lines.append("\n".join(body))
    return group_id


def generate():
    app_sources = swift_files(APP)
    unit_sources = swift_files(UNIT_TESTS)
    ui_sources = swift_files(UI_TESTS)
    unit_resources = fixture_files(f"{UNIT_TESTS}/Fixtures")
    storekit_configuration = f"{APP}/Resources/Odomind.storekit"

    assets = f"{APP}/Resources/Assets.xcassets"
    info_plist = f"{APP}/Resources/Info.plist"

    if not app_sources:
        raise SystemExit("No app sources found — run this from the repository root.")

    all_paths = (
        app_sources + unit_sources + ui_sources + unit_resources
        + [assets, info_plist, storekit_configuration]
    )

    # --- identifiers -------------------------------------------------------
    file_refs = {path: oid("fileref", path) for path in all_paths}
    build_files = {}
    for path in app_sources:
        build_files[("app", path)] = oid("buildfile", "app", path)
    build_files[("app", assets)] = oid("buildfile", "app", assets)
    for path in unit_sources:
        build_files[("unit", path)] = oid("buildfile", "unit", path)
    for path in unit_resources:
        build_files[("unit", path)] = oid("buildfile", "unit", path)
    for path in ui_sources:
        build_files[("ui", path)] = oid("buildfile", "ui", path)

    ids = {
        "project": oid("project", "Odomind"),
        "mainGroup": oid("group", "root"),
        "productsGroup": oid("group", "Products"),
        "appProduct": oid("product", APP),
        "unitProduct": oid("product", UNIT_TESTS),
        "uiProduct": oid("product", UI_TESTS),
        "packageRef": oid("packageref", "OdomindCore"),
        "appPackageProduct": oid("packageproduct", "app", "OdomindCore"),
        "unitPackageProduct": oid("packageproduct", "unit", "OdomindCore"),
        "appPackageBuildFile": oid("buildfile", "app", "OdomindCore"),
        "unitPackageBuildFile": oid("buildfile", "unit", "OdomindCore"),
    }
    for target in (APP, UNIT_TESTS, UI_TESTS):
        ids[f"{target}.target"] = oid("target", target)
        ids[f"{target}.sources"] = oid("phase", "sources", target)
        ids[f"{target}.frameworks"] = oid("phase", "frameworks", target)
        ids[f"{target}.resources"] = oid("phase", "resources", target)
        ids[f"{target}.configList"] = oid("configlist", target)
        ids[f"{target}.debug"] = oid("config", target, "Debug")
        ids[f"{target}.release"] = oid("config", target, "Release")
    ids["project.configList"] = oid("configlist", "project")
    ids["project.debug"] = oid("config", "project", "Debug")
    ids["project.release"] = oid("config", "project", "Release")
    for target in (UNIT_TESTS, UI_TESTS):
        ids[f"{target}.dependency"] = oid("dependency", target)
        ids[f"{target}.proxy"] = oid("proxy", target)

    out = ["// !$*UTF8*$!", "{"]
    out.append("\tarchiveVersion = 1;")
    out.append("\tclasses = {")
    out.append("\t};")
    out.append("\tobjectVersion = 56;")
    out.append("\tobjects = {")

    # --- PBXBuildFile ------------------------------------------------------
    out.append("\n/* Begin PBXBuildFile section */")
    for (target, path), identifier in sorted(build_files.items(), key=lambda item: item[1]):
        name = pathlib.Path(path).name
        out.append(
            f"\t\t{identifier} /* {name} in {target} */ = {{isa = PBXBuildFile; "
            f"fileRef = {file_refs[path]} /* {name} */; }};"
        )
    out.append(
        f"\t\t{ids['appPackageBuildFile']} /* OdomindCore in Frameworks */ = {{isa = PBXBuildFile; "
        f"productRef = {ids['appPackageProduct']} /* OdomindCore */; }};"
    )
    out.append(
        f"\t\t{ids['unitPackageBuildFile']} /* OdomindCore in Frameworks */ = {{isa = PBXBuildFile; "
        f"productRef = {ids['unitPackageProduct']} /* OdomindCore */; }};"
    )
    out.append("/* End PBXBuildFile section */")

    # --- PBXContainerItemProxy --------------------------------------------
    out.append("\n/* Begin PBXContainerItemProxy section */")
    for target in (UNIT_TESTS, UI_TESTS):
        out.append(f"\t\t{ids[f'{target}.proxy']} /* PBXContainerItemProxy */ = {{")
        out.append("\t\t\tisa = PBXContainerItemProxy;")
        out.append(f"\t\t\tcontainerPortal = {ids['project']} /* Project object */;")
        out.append("\t\t\tproxyType = 1;")
        out.append(f"\t\t\tremoteGlobalIDString = {ids[f'{APP}.target']};")
        out.append(f"\t\t\tremoteInfo = {APP};")
        out.append("\t\t};")
    out.append("/* End PBXContainerItemProxy section */")

    # --- PBXFileReference --------------------------------------------------
    out.append("\n/* Begin PBXFileReference section */")
    for path in sorted(all_paths):
        name = pathlib.Path(path).name
        out.append(
            f"\t\t{file_refs[path]} /* {name} */ = {{isa = PBXFileReference; "
            f"lastKnownFileType = {file_type(path)}; path = {quoted(name)}; "
            f'sourceTree = "<group>"; }};'
        )
    out.append(
        f"\t\t{ids['appProduct']} /* {APP}.app */ = {{isa = PBXFileReference; "
        f"explicitFileType = wrapper.application; includeInIndex = 0; "
        f"path = {APP}.app; sourceTree = BUILT_PRODUCTS_DIR; }};"
    )
    for target, key in ((UNIT_TESTS, "unitProduct"), (UI_TESTS, "uiProduct")):
        out.append(
            f"\t\t{ids[key]} /* {target}.xctest */ = {{isa = PBXFileReference; "
            f"explicitFileType = wrapper.cfbundle; includeInIndex = 0; "
            f"path = {target}.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};"
        )
    out.append("/* End PBXFileReference section */")

    # --- PBXFrameworksBuildPhase ------------------------------------------
    out.append("\n/* Begin PBXFrameworksBuildPhase section */")
    for target in (APP, UNIT_TESTS, UI_TESTS):
        out.append(f"\t\t{ids[f'{target}.frameworks']} /* Frameworks */ = {{")
        out.append("\t\t\tisa = PBXFrameworksBuildPhase;")
        out.append("\t\t\tbuildActionMask = 2147483647;")
        out.append("\t\t\tfiles = (")
        if target == APP:
            out.append(f"\t\t\t\t{ids['appPackageBuildFile']} /* OdomindCore in Frameworks */,")
        elif target == UNIT_TESTS:
            out.append(f"\t\t\t\t{ids['unitPackageBuildFile']} /* OdomindCore in Frameworks */,")
        out.append("\t\t\t);")
        out.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        out.append("\t\t};")
    out.append("/* End PBXFrameworksBuildPhase section */")

    # --- PBXGroup ----------------------------------------------------------
    group_lines = []
    top_level_ids = []
    for name, paths in (
        (APP, app_sources + [assets, info_plist]),
        (UNIT_TESTS, unit_sources + unit_resources),
        (UI_TESTS, ui_sources),
    ):
        tree = Tree(name, name)
        for path in paths:
            tree.add(str(pathlib.Path(path).relative_to(name)), path)
        top_level_ids.append(build_groups(tree, name, group_lines, file_refs))

    products = [f"\t\t{ids['productsGroup']} /* Products */ = {{"]
    products.append("\t\t\tisa = PBXGroup;")
    products.append("\t\t\tchildren = (")
    for key in ("appProduct", "unitProduct", "uiProduct"):
        products.append(f"\t\t\t\t{ids[key]},")
    products.append("\t\t\t);")
    products.append("\t\t\tname = Products;")
    products.append('\t\t\tsourceTree = "<group>";')
    products.append("\t\t};")
    group_lines.append("\n".join(products))

    root = [f"\t\t{ids['mainGroup']} = {{"]
    root.append("\t\t\tisa = PBXGroup;")
    root.append("\t\t\tchildren = (")
    for identifier in top_level_ids:
        root.append(f"\t\t\t\t{identifier},")
    root.append(f"\t\t\t\t{ids['productsGroup']} /* Products */,")
    root.append("\t\t\t);")
    root.append('\t\t\tsourceTree = "<group>";')
    root.append("\t\t};")
    group_lines.append("\n".join(root))

    out.append("\n/* Begin PBXGroup section */")
    out.extend(group_lines)
    out.append("/* End PBXGroup section */")

    # --- PBXNativeTarget ---------------------------------------------------
    out.append("\n/* Begin PBXNativeTarget section */")
    target_specs = [
        (APP, "com.apple.product-type.application", "appProduct", [], ["appPackageProduct"]),
        (
            UNIT_TESTS,
            "com.apple.product-type.bundle.unit-test",
            "unitProduct",
            [ids[f"{UNIT_TESTS}.dependency"]],
            ["unitPackageProduct"],
        ),
        (UI_TESTS, "com.apple.product-type.bundle.ui-testing", "uiProduct", [ids[f"{UI_TESTS}.dependency"]], []),
    ]
    for target, product_type, product_key, dependencies, package_products in target_specs:
        out.append(f"\t\t{ids[f'{target}.target']} /* {target} */ = {{")
        out.append("\t\t\tisa = PBXNativeTarget;")
        out.append(
            f"\t\t\tbuildConfigurationList = {ids[f'{target}.configList']} "
            f'/* Build configuration list for PBXNativeTarget "{target}" */;'
        )
        out.append("\t\t\tbuildPhases = (")
        out.append(f"\t\t\t\t{ids[f'{target}.sources']} /* Sources */,")
        out.append(f"\t\t\t\t{ids[f'{target}.frameworks']} /* Frameworks */,")
        out.append(f"\t\t\t\t{ids[f'{target}.resources']} /* Resources */,")
        out.append("\t\t\t);")
        out.append("\t\t\tbuildRules = (")
        out.append("\t\t\t);")
        out.append("\t\t\tdependencies = (")
        for dependency in dependencies:
            out.append(f"\t\t\t\t{dependency},")
        out.append("\t\t\t);")
        out.append(f"\t\t\tname = {target};")
        if package_products:
            out.append("\t\t\tpackageProductDependencies = (")
            for key in package_products:
                out.append(f"\t\t\t\t{ids[key]} /* OdomindCore */,")
            out.append("\t\t\t);")
        out.append(f"\t\t\tproductName = {target};")
        out.append(f"\t\t\tproductReference = {ids[product_key]};")
        out.append(f'\t\t\tproductType = "{product_type}";')
        out.append("\t\t};")
    out.append("/* End PBXNativeTarget section */")

    # --- PBXProject --------------------------------------------------------
    out.append("\n/* Begin PBXProject section */")
    out.append(f"\t\t{ids['project']} /* Project object */ = {{")
    out.append("\t\t\tisa = PBXProject;")
    out.append("\t\t\tattributes = {")
    out.append("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    out.append("\t\t\t\tLastSwiftUpdateCheck = 1600;")
    out.append("\t\t\t\tLastUpgradeCheck = 1600;")
    out.append("\t\t\t\tTargetAttributes = {")
    out.append(f"\t\t\t\t\t{ids[f'{APP}.target']} = {{")
    out.append("\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;")
    out.append("\t\t\t\t\t};")
    out.append(f"\t\t\t\t\t{ids[f'{UNIT_TESTS}.target']} = {{")
    out.append("\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;")
    out.append(f"\t\t\t\t\t\tTestTargetID = {ids[f'{APP}.target']};")
    out.append("\t\t\t\t\t};")
    out.append(f"\t\t\t\t\t{ids[f'{UI_TESTS}.target']} = {{")
    out.append("\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;")
    out.append(f"\t\t\t\t\t\tTestTargetID = {ids[f'{APP}.target']};")
    out.append("\t\t\t\t\t};")
    out.append("\t\t\t\t};")
    out.append("\t\t\t};")
    out.append(
        f"\t\t\tbuildConfigurationList = {ids['project.configList']} "
        '/* Build configuration list for PBXProject "Odomind" */;'
    )
    out.append('\t\t\tcompatibilityVersion = "Xcode 14.0";')
    out.append("\t\t\tdevelopmentRegion = en;")
    out.append("\t\t\thasScannedForEncodings = 0;")
    out.append("\t\t\tknownRegions = (")
    out.append("\t\t\t\ten,")
    out.append("\t\t\t\tBase,")
    out.append("\t\t\t);")
    out.append(f"\t\t\tmainGroup = {ids['mainGroup']};")
    out.append("\t\t\tpackageReferences = (")
    out.append(f"\t\t\t\t{ids['packageRef']} /* XCLocalSwiftPackageReference \"OdomindCore\" */,")
    out.append("\t\t\t);")
    out.append(f"\t\t\tproductRefGroup = {ids['productsGroup']} /* Products */;")
    out.append('\t\t\tprojectDirPath = "";')
    out.append('\t\t\tprojectRoot = "";')
    out.append("\t\t\ttargets = (")
    for target in (APP, UNIT_TESTS, UI_TESTS):
        out.append(f"\t\t\t\t{ids[f'{target}.target']} /* {target} */,")
    out.append("\t\t\t);")
    out.append("\t\t};")
    out.append("/* End PBXProject section */")

    # --- PBXResourcesBuildPhase -------------------------------------------
    out.append("\n/* Begin PBXResourcesBuildPhase section */")
    # The StoreKit configuration is referenced by the scheme, not copied into
    # the app. It is a development artifact: shipping it would put a list of
    # product identifiers and placeholder prices inside the binary.
    resource_map = {APP: [assets], UNIT_TESTS: unit_resources, UI_TESTS: []}
    for target in (APP, UNIT_TESTS, UI_TESTS):
        key = {APP: "app", UNIT_TESTS: "unit", UI_TESTS: "ui"}[target]
        out.append(f"\t\t{ids[f'{target}.resources']} /* Resources */ = {{")
        out.append("\t\t\tisa = PBXResourcesBuildPhase;")
        out.append("\t\t\tbuildActionMask = 2147483647;")
        out.append("\t\t\tfiles = (")
        for path in resource_map[target]:
            out.append(f"\t\t\t\t{build_files[(key, path)]} /* {pathlib.Path(path).name} */,")
        out.append("\t\t\t);")
        out.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        out.append("\t\t};")
    out.append("/* End PBXResourcesBuildPhase section */")

    # --- PBXSourcesBuildPhase ---------------------------------------------
    out.append("\n/* Begin PBXSourcesBuildPhase section */")
    source_map = {APP: ("app", app_sources), UNIT_TESTS: ("unit", unit_sources), UI_TESTS: ("ui", ui_sources)}
    for target in (APP, UNIT_TESTS, UI_TESTS):
        key, paths = source_map[target]
        out.append(f"\t\t{ids[f'{target}.sources']} /* Sources */ = {{")
        out.append("\t\t\tisa = PBXSourcesBuildPhase;")
        out.append("\t\t\tbuildActionMask = 2147483647;")
        out.append("\t\t\tfiles = (")
        for path in paths:
            out.append(f"\t\t\t\t{build_files[(key, path)]} /* {pathlib.Path(path).name} */,")
        out.append("\t\t\t);")
        out.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        out.append("\t\t};")
    out.append("/* End PBXSourcesBuildPhase section */")

    # --- PBXTargetDependency ----------------------------------------------
    out.append("\n/* Begin PBXTargetDependency section */")
    for target in (UNIT_TESTS, UI_TESTS):
        out.append(f"\t\t{ids[f'{target}.dependency']} /* PBXTargetDependency */ = {{")
        out.append("\t\t\tisa = PBXTargetDependency;")
        out.append(f"\t\t\ttarget = {ids[f'{APP}.target']} /* {APP} */;")
        out.append(f"\t\t\ttargetProxy = {ids[f'{target}.proxy']} /* PBXContainerItemProxy */;")
        out.append("\t\t};")
    out.append("/* End PBXTargetDependency section */")

    # --- XCBuildConfiguration ---------------------------------------------
    shared = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
        "CLANG_ANALYZER_NONNULL": "YES",
        "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION": "YES_AGGRESSIVE",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "CLANG_ENABLE_OBJC_WEAK": "YES",
        "CLANG_WARN_BOOL_CONVERSION": "YES",
        "CLANG_WARN_CONSTANT_CONVERSION": "YES",
        "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
        "CLANG_WARN_EMPTY_BODY": "YES",
        "CLANG_WARN_ENUM_CONVERSION": "YES",
        "CLANG_WARN_INFINITE_RECURSION": "YES",
        "CLANG_WARN_INT_CONVERSION": "YES",
        "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "YES",
        "CLANG_WARN_STRICT_PROTOTYPES": "YES",
        "CLANG_WARN_SUSPICIOUS_MOVE": "YES",
        "CLANG_WARN_UNREACHABLE_CODE": "YES",
        "CLANG_WARN__DUPLICATE_METHOD_MATCH": "YES",
        "COPY_PHASE_STRIP": "NO",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "GCC_C_LANGUAGE_STANDARD": "gnu17",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
        "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
        "GCC_WARN_UNDECLARED_SELECTOR": "YES",
        "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
        "GCC_WARN_UNUSED_FUNCTION": "YES",
        "GCC_WARN_UNUSED_VARIABLE": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
        "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
        "MTL_FAST_MATH": "YES",
        "SDKROOT": "iphoneos",
        "SWIFT_VERSION": SWIFT_VERSION,
    }
    debug_only = {
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "ENABLE_TESTABILITY": "YES",
        "GCC_DYNAMIC_NO_PIC": "NO",
        "GCC_OPTIMIZATION_LEVEL": "0",
        "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
        "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
        "ONLY_ACTIVE_ARCH": "YES",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
    }
    release_only = {
        "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
        "ENABLE_NS_ASSERTIONS": "NO",
        "MTL_ENABLE_DEBUG_INFO": "NO",
        "SWIFT_COMPILATION_MODE": "wholemodule",
        "VALIDATE_PRODUCT": "YES",
    }

    app_settings = {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": PROJECT_VERSION,
        # Left empty on purpose: no team, certificate or profile belongs in
        # source control. Set yours in Signing & Capabilities to run on a device.
        "DEVELOPMENT_TEAM": "",
        "ENABLE_PREVIEWS": "YES",
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": info_plist,
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
        "MARKETING_VERSION": MARKETING_VERSION,
        "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "TARGETED_DEVICE_FAMILY": "1,2",
    }
    unit_settings = {
        "BUNDLE_LOADER": "$(TEST_HOST)",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": PROJECT_VERSION,
        "DEVELOPMENT_TEAM": "",
        "GENERATE_INFOPLIST_FILE": "YES",
        "MARKETING_VERSION": MARKETING_VERSION,
        "PRODUCT_BUNDLE_IDENTIFIER": f"{BUNDLE_ID}.tests",
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "TARGETED_DEVICE_FAMILY": "1,2",
        "TEST_HOST": f"$(BUILT_PRODUCTS_DIR)/{APP}.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/{APP}",
    }
    ui_settings = {
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": PROJECT_VERSION,
        "DEVELOPMENT_TEAM": "",
        "GENERATE_INFOPLIST_FILE": "YES",
        "MARKETING_VERSION": MARKETING_VERSION,
        "PRODUCT_BUNDLE_IDENTIFIER": f"{BUNDLE_ID}.uitests",
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "TARGETED_DEVICE_FAMILY": "1,2",
        "TEST_TARGET_NAME": APP,
    }

    out.append("\n/* Begin XCBuildConfiguration section */")

    def emit_config(identifier, name, settings):
        out.append(f"\t\t{identifier} /* {name} */ = {{")
        out.append("\t\t\tisa = XCBuildConfiguration;")
        out.append("\t\t\tbuildSettings = {")
        out.append(settings_block(settings, 4))
        out.append("\t\t\t};")
        out.append(f"\t\t\tname = {name};")
        out.append("\t\t};")

    emit_config(ids["project.debug"], "Debug", {**shared, **debug_only})
    emit_config(ids["project.release"], "Release", {**shared, **release_only})
    for target, settings in ((APP, app_settings), (UNIT_TESTS, unit_settings), (UI_TESTS, ui_settings)):
        emit_config(ids[f"{target}.debug"], "Debug", settings)
        emit_config(ids[f"{target}.release"], "Release", settings)
    out.append("/* End XCBuildConfiguration section */")

    # --- XCConfigurationList ----------------------------------------------
    out.append("\n/* Begin XCConfigurationList section */")

    def emit_list(identifier, label, debug_id, release_id):
        out.append(f"\t\t{identifier} /* Build configuration list for {label} */ = {{")
        out.append("\t\t\tisa = XCConfigurationList;")
        out.append("\t\t\tbuildConfigurations = (")
        out.append(f"\t\t\t\t{debug_id} /* Debug */,")
        out.append(f"\t\t\t\t{release_id} /* Release */,")
        out.append("\t\t\t);")
        out.append("\t\t\tdefaultConfigurationIsVisible = 0;")
        out.append("\t\t\tdefaultConfigurationName = Release;")
        out.append("\t\t};")

    emit_list(ids["project.configList"], 'PBXProject "Odomind"', ids["project.debug"], ids["project.release"])
    for target in (APP, UNIT_TESTS, UI_TESTS):
        emit_list(
            ids[f"{target}.configList"],
            f'PBXNativeTarget "{target}"',
            ids[f"{target}.debug"],
            ids[f"{target}.release"],
        )
    out.append("/* End XCConfigurationList section */")

    # --- Swift package -----------------------------------------------------
    out.append("\n/* Begin XCLocalSwiftPackageReference section */")
    out.append(f"\t\t{ids['packageRef']} /* XCLocalSwiftPackageReference \"OdomindCore\" */ = {{")
    out.append("\t\t\tisa = XCLocalSwiftPackageReference;")
    out.append("\t\t\trelativePath = OdomindCore;")
    out.append("\t\t};")
    out.append("/* End XCLocalSwiftPackageReference section */")

    out.append("\n/* Begin XCSwiftPackageProductDependency section */")
    for key in ("appPackageProduct", "unitPackageProduct"):
        out.append(f"\t\t{ids[key]} /* OdomindCore */ = {{")
        out.append("\t\t\tisa = XCSwiftPackageProductDependency;")
        out.append("\t\t\tproductName = OdomindCore;")
        out.append("\t\t};")
    out.append("/* End XCSwiftPackageProductDependency section */")

    out.append("\t};")
    out.append(f"\trootObject = {ids['project']} /* Project object */;")
    out.append("}")

    return "\n".join(out) + "\n", ids


def write_scheme(ids):
    scheme_dir = PROJECT / "xcshareddata" / "xcschemes"
    scheme_dir.mkdir(parents=True, exist_ok=True)
    scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
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
               BlueprintIdentifier = "{ids[f'{APP}.target']}"
               BuildableName = "{APP}.app"
               BlueprintName = "{APP}"
               ReferencedContainer = "container:Odomind.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference
            skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{ids[f'{UNIT_TESTS}.target']}"
               BuildableName = "{UNIT_TESTS}.xctest"
               BlueprintName = "{UNIT_TESTS}"
               ReferencedContainer = "container:Odomind.xcodeproj">
            </BuildableReference>
         </TestableReference>
         <TestableReference
            skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{ids[f'{UI_TESTS}.target']}"
               BuildableName = "{UI_TESTS}.xctest"
               BlueprintName = "{UI_TESTS}"
               ReferencedContainer = "container:Odomind.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
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
      allowLocationSimulation = "NO">
      <StoreKitConfigurationFileReference
         identifier = "../../../Odomind/Resources/Odomind.storekit">
      </StoreKitConfigurationFileReference>
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{ids[f'{APP}.target']}"
            BuildableName = "{APP}.app"
            BlueprintName = "{APP}"
            ReferencedContainer = "container:Odomind.xcodeproj">
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
            BlueprintIdentifier = "{ids[f'{APP}.target']}"
            BuildableName = "{APP}.app"
            BlueprintName = "{APP}"
            ReferencedContainer = "container:Odomind.xcodeproj">
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
"""
    (scheme_dir / f"{APP}.xcscheme").write_text(scheme)

    workspace = PROJECT / "project.xcworkspace"
    workspace.mkdir(parents=True, exist_ok=True)
    (workspace / "contents.xcworkspacedata").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<Workspace\n'
        '   version = "1.0">\n'
        '   <FileRef\n'
        '      location = "self:">\n'
        '   </FileRef>\n'
        '</Workspace>\n'
    )


def main():
    pbxproj, ids = generate()
    PROJECT.mkdir(parents=True, exist_ok=True)
    (PROJECT / "project.pbxproj").write_text(pbxproj)
    write_scheme(ids)
    print(f"wrote {PROJECT.relative_to(ROOT)}/project.pbxproj ({len(pbxproj)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
