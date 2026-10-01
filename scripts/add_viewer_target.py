#!/usr/bin/env python3
"""
Add the "QLMarkdown Viewer" app target to QLMarkdown.xcodeproj.

The viewer compiles exactly the same rendering sources as the Quick Look extension
(cmark-gfm, cmark-extra, Settings, Settings+render, ...) and links the same libraries;
only the host code (the `QLMarkdownViewer` folder) differs.

The target is derived from the "Markdown QL Extension" target at run time, so the script
can be re-run after pulling upstream changes (restore the upstream project.pbxproj first).

Usage: python3 scripts/add_viewer_target.py
"""
import re
import secrets
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PBXPROJ = ROOT / "QLMarkdown.xcodeproj" / "project.pbxproj"

TARGET_NAME = "QLMarkdown Viewer"
SOURCE_DIR = "QLMarkdownViewer"
BUNDLE_ID = "org.sbarex.QLMarkdown.Viewer"
TEMPLATE_TARGET = "Markdown QL Extension"
# Host specific sources of the template target that the viewer replaces with its own.
EXCLUDED_SOURCES = {"PreviewProvider.swift", "AboutViewController.swift"}
EXCLUDED_FRAMEWORKS = {"Quartz.framework"}
# Bundled resources needed by the renderer (looked up through `Settings.resourceBundle`).
RESOURCES = ["default.css", "highlight", "mermaid.min.js.gz", "tex-mml-chtml.js.gz", "icon.icon"]

text = PBXPROJ.read_text()
if f'name = "{TARGET_NAME}";' in text:
    sys.exit(f"Target '{TARGET_NAME}' already exists.")

used_ids = set(re.findall(r"\b[0-9A-F]{24}\b", text))


def new_id() -> str:
    while True:
        i = secrets.token_hex(12).upper()
        if i not in used_ids:
            used_ids.add(i)
            return i


def get_object(oid: str) -> str:
    """Body of the object `oid`, single or multi line."""
    m = re.search(rf"^\t\t{oid} (?:/\* .*? \*/ )?= \{{isa = .*?\}};$", text, re.M)
    if m:
        return m.group(0)
    m = re.search(rf"^\t\t{oid} (?:/\* .*? \*/ )?= \{{\n.*?^\t\t\}};$", text, re.M | re.S)
    if not m:
        raise KeyError(oid)
    return m.group(0)


def list_items(body: str, key: str) -> list[str]:
    """IDs listed in the array `key` of an object body."""
    m = re.search(rf"\b{key} = \((.*?)\);", body, re.S)
    return re.findall(r"\b([0-9A-F]{24})\b", m.group(1)) if m else []


new_objects: dict[str, list[str]] = {}


def add_object(isa: str, obj: str):
    new_objects.setdefault(isa, []).append(obj)


def append_to_list(owner_id: str, key: str, item: str):
    global text
    body = get_object(owner_id)
    new_body = re.sub(rf"(\b{key} = \(\n)(.*?)(^\t+\);)", lambda m: m.group(1) + m.group(2) + item + "\n" + m.group(3), body, count=1, flags=re.S | re.M)
    text = text.replace(body, new_body)


def find_target(name: str) -> str:
    m = re.search(rf"^\t\t([0-9A-F]{{24}}) /\* {re.escape(name)} \*/ = \{{\n\t\t\tisa = PBXNativeTarget;", text, re.M)
    return m.group(1)


project_id = re.search(r"rootObject = ([0-9A-F]{24})", text).group(1)
project = get_object(project_id)
main_group = re.search(r"mainGroup = ([0-9A-F]{24})", project).group(1)
products_group = re.search(r"productRefGroup = ([0-9A-F]{24})", project).group(1)

template_id = find_target(TEMPLATE_TARGET)
template = get_object(template_id)
phases = list_items(template, "buildPhases")
phase_by_isa = {}
for p in phases:
    isa = re.search(r"isa = (\w+);", get_object(p)).group(1)
    phase_by_isa[isa] = p

target_id = new_id()


def clone_build_files(phase_id: str, exclude: set[str], phase_name: str) -> list[str]:
    ids = []
    for bf in list_items(get_object(phase_id), "files"):
        body = get_object(bf)
        ref = re.search(r"(?:fileRef|productRef) = ([0-9A-F]{24}) /\* (.*?) \*/", body)
        if ref.group(2) in exclude:
            continue
        nid = new_id()
        nbody = body.replace(bf, nid, 1)
        nbody = re.sub(r" in \w[\w ]*? \*/ = ", f" in {phase_name} */ = ", nbody, count=1)
        if "productRef" in body:
            # Package products must be referenced by the new target's own product dependencies.
            nbody = nbody.replace(ref.group(1), package_products[ref.group(1)])
        add_object("PBXBuildFile", nbody)
        ids.append(nid)
    return ids


# Swift package products (Yams, SwiftSoup).
package_products = {}
for pp in list_items(template, "packageProductDependencies"):
    nid = new_id()
    package_products[pp] = nid
    add_object("XCSwiftPackageProductDependency", get_object(pp).replace(pp, nid, 1))

# Sources / Frameworks.
source_files = clone_build_files(phase_by_isa["PBXSourcesBuildPhase"], EXCLUDED_SOURCES, "Sources")
framework_files = clone_build_files(phase_by_isa["PBXFrameworksBuildPhase"], EXCLUDED_FRAMEWORKS, "Frameworks")

# Resources, taken from the main app's resources phase.
app_resources = {}
app_template = get_object(find_target("QLMarkdown"))
for p in list_items(app_template, "buildPhases"):
    body = get_object(p)
    if "isa = PBXResourcesBuildPhase;" in body:
        for bf in list_items(body, "files"):
            ref = re.search(r"fileRef = ([0-9A-F]{24}) /\* (.*?) \*/", get_object(bf))
            app_resources[ref.group(2)] = ref.group(1)
resource_files = []
for name in RESOURCES:
    nid = new_id()
    add_object("PBXBuildFile", f"\t\t{nid} /* {name} in Resources */ = {{isa = PBXBuildFile; fileRef = {app_resources[name]} /* {name} */; }};")
    resource_files.append(nid)

# Embedded dylib (libwrapper_highlight).
embed_files = []
m = re.search(r"^\t\t[0-9A-F]{24} /\* (libwrapper_highlight\.dylib) in Embed Libraries \*/ = \{isa = PBXBuildFile; fileRef = ([0-9A-F]{24}) .*$", text, re.M)
nid = new_id()
add_object("PBXBuildFile", f"\t\t{nid} /* libwrapper_highlight.dylib in Embed Libraries */ = {{isa = PBXBuildFile; fileRef = {m.group(2)} /* libwrapper_highlight.dylib */; settings = {{ATTRIBUTES = (CodeSignOnCopy, ); }}; }};")
embed_files.append(nid)


def phase(isa, name, ids, extra=""):
    pid = new_id()
    entries = []
    for i in ids:
        c = re.search(rf"^\t\t{i} /\* (.*?) \*/", "\n".join(sum(new_objects.values(), [])), re.M).group(1)
        entries.append(f"\t\t\t\t{i} /* {c} */,\n")
    add_object(isa, f"""\t\t{pid} /* {name} */ = {{
\t\t\tisa = {isa};
\t\t\tbuildActionMask = 2147483647;
{extra}\t\t\tfiles = (
{''.join(entries)}\t\t\t);
{'' if isa != 'PBXCopyFilesBuildPhase' else f'			name = "{name}";' + chr(10)}\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};""")
    return pid, name


phase_list = [
    phase("PBXSourcesBuildPhase", "Sources", source_files),
    phase("PBXFrameworksBuildPhase", "Frameworks", framework_files),
    phase("PBXResourcesBuildPhase", "Resources", resource_files),
    phase("PBXCopyFilesBuildPhase", "Embed Libraries", embed_files, '\t\t\tdstPath = "";\n\t\t\tdstSubfolderSpec = 10;\n'),
]

# Dependencies (skip stale ones pointing to targets that no longer exist).
dep_ids = []
for dep in list_items(template, "dependencies"):
    body = get_object(dep)
    product = re.search(r"productRef = ([0-9A-F]{24})", body)
    if product:
        # Dependency on a Swift package product.
        nprod = new_id()
        ndep = new_id()
        add_object("XCSwiftPackageProductDependency", get_object(product.group(1)).replace(product.group(1), nprod, 1))
        add_object("PBXTargetDependency", body.replace(dep, ndep, 1).replace(product.group(1), nprod))
        dep_ids.append(ndep)
        continue
    proxy_id = re.search(r"targetProxy = ([0-9A-F]{24})", body).group(1)
    proxy = get_object(proxy_id)
    remote = re.search(r"remoteGlobalIDString = ([0-9A-F]{24})", proxy).group(1)
    is_local = project_id in proxy
    if is_local and not re.search(rf"^\t\t{remote} /\* .*? \*/ = \{{\n\t\t\tisa = PBX\w*Target;", text, re.M):
        continue
    nproxy = new_id()
    ndep = new_id()
    add_object("PBXContainerItemProxy", proxy.replace(proxy_id, nproxy, 1))
    add_object("PBXTargetDependency", body.replace(dep, ndep, 1).replace(proxy_id, nproxy))
    dep_ids.append(ndep)

# Build configurations.
config_list_id = re.search(r"buildConfigurationList = ([0-9A-F]{24})", template).group(1)
config_ids = []
for cfg in list_items(get_object(config_list_id), "buildConfigurations"):
    body = get_object(cfg)
    nid = new_id()
    body = body.replace(cfg, nid, 1)
    s = body
    for key in ("APPLICATION_EXTENSION_API_ONLY", "CODE_SIGN_ENTITLEMENTS", "REGISTER_APP_GROUPS", "SKIP_INSTALL", "PROVISIONING_PROFILE_SPECIFIER", "DEVELOPMENT_TEAM", r'"CODE_SIGN_IDENTITY\[sdk=macosx\*\]"', "CODE_SIGN_IDENTITY", "CODE_SIGN_STYLE"):
        s = re.sub(rf"^\t\t\t\t{key} = .*;\n", "", s, flags=re.M)
    s = re.sub(r"INFOPLIST_FILE = .*;", f"INFOPLIST_FILE = {SOURCE_DIR}/Info.plist;", s)
    s = re.sub(r"PRODUCT_BUNDLE_IDENTIFIER = .*;", f"PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};", s)
    s = re.sub(r"LD_RUNPATH_SEARCH_PATHS = \(.*?\);", 'LD_RUNPATH_SEARCH_PATHS = (\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t\t"@executable_path/../Frameworks",\n\t\t\t\t);', s, flags=re.S)
    extra = (
        "\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = icon;\n"
        '\t\t\t\tCODE_SIGN_IDENTITY = "-";\n'
        "\t\t\t\tCODE_SIGN_STYLE = Manual;\n"
        "\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;\n"
        "\t\t\t\tENABLE_APP_SANDBOX = NO;\n"
        "\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = \"$(TARGET_NAME)\";\n"
    )
    s = s.replace("\t\t\tbuildSettings = {\n", "\t\t\tbuildSettings = {\n" + extra, 1)
    add_object("XCBuildConfiguration", s)
    config_ids.append((nid, re.search(r"name = (\w+);", s).group(1)))

new_config_list = new_id()
add_object("XCConfigurationList", f"""\t\t{new_config_list} /* Build configuration list for PBXNativeTarget "{TARGET_NAME}" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
{''.join(f'				{i} /* {n} */,{chr(10)}' for i, n in config_ids)}\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};""")

# Product and synchronized source folder.
product_id = new_id()
add_object("PBXFileReference", f'\t\t{product_id} /* {TARGET_NAME}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "{TARGET_NAME}.app"; sourceTree = BUILT_PRODUCTS_DIR; }};')
exception_id = new_id()
add_object("PBXFileSystemSynchronizedBuildFileExceptionSet", f"""\t\t{exception_id} /* PBXFileSystemSynchronizedBuildFileExceptionSet */ = {{
\t\t\tisa = PBXFileSystemSynchronizedBuildFileExceptionSet;
\t\t\tmembershipExceptions = (
\t\t\t\tInfo.plist,
\t\t\t);
\t\t\ttarget = {target_id} /* {TARGET_NAME} */;
\t\t}};""")
group_id = new_id()
add_object("PBXFileSystemSynchronizedRootGroup", f'\t\t{group_id} /* {SOURCE_DIR} */ = {{isa = PBXFileSystemSynchronizedRootGroup; exceptions = ({exception_id} /* PBXFileSystemSynchronizedBuildFileExceptionSet */, ); explicitFileTypes = {{}}; explicitFolders = (); path = {SOURCE_DIR}; sourceTree = "<group>"; }};')

add_object("PBXNativeTarget", f"""\t\t{target_id} /* {TARGET_NAME} */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {new_config_list} /* Build configuration list for PBXNativeTarget "{TARGET_NAME}" */;
\t\t\tbuildPhases = (
{''.join(f'				{i} /* {n} */,{chr(10)}' for i, n in phase_list)}\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
{''.join(f'				{i} /* PBXTargetDependency */,{chr(10)}' for i in dep_ids)}\t\t\t);
\t\t\tfileSystemSynchronizedGroups = (
\t\t\t\t{group_id} /* {SOURCE_DIR} */,
\t\t\t);
\t\t\tname = "{TARGET_NAME}";
\t\t\tpackageProductDependencies = (
{''.join(f'				{i} /* {re.search(r"productName = (.*?);", get_object(p)).group(1)} */,{chr(10)}' for p, i in package_products.items())}\t\t\t);
\t\t\tproductName = "{TARGET_NAME}";
\t\t\tproductReference = {product_id} /* {TARGET_NAME}.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};""")

# Insert the new objects into their sections.
for isa, objs in new_objects.items():
    marker = f"/* End {isa} section */"
    if marker not in text:
        raise SystemExit(f"Missing section {isa}")
    text = text.replace(marker, "\n".join(objs) + "\n" + marker, 1)

append_to_list(project_id, "targets", f"\t\t\t\t{target_id} /* {TARGET_NAME} */,")
append_to_list(main_group, "children", f"\t\t\t\t{group_id} /* {SOURCE_DIR} */,")
append_to_list(products_group, "children", f"\t\t\t\t{product_id} /* {TARGET_NAME}.app */,")

PBXPROJ.write_text(text)

# Shared scheme.
scheme_dir = PBXPROJ.parent / "xcshareddata" / "xcschemes"
template_scheme = (scheme_dir / "QLMarkdown.xcscheme").read_text()
app_id = find_target("QLMarkdown")
scheme = (template_scheme
          .replace(app_id, target_id)
          .replace('BuildableName = "QLMarkdown.app"', f'BuildableName = "{TARGET_NAME}.app"')
          .replace('BlueprintName = "QLMarkdown"', f'BlueprintName = "{TARGET_NAME}"'))
(scheme_dir / f"{TARGET_NAME}.xcscheme").write_text(scheme)
print(f"Added target '{TARGET_NAME}' ({target_id}).")
