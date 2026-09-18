# -*- coding: utf-8 -*-
"""UPDATE-001：复刻 Dart 端 version.json 解析逻辑的函数测试（UPDATE-001）。

用途：在没有 Flutter 构建环境的沙箱里，先用 Python 验证与 Dart 等价的
「宽容解析 + 语义化版本比较」逻辑是否正确；验证通过后逻辑保持不变，
Dart 端代码见 lib/features/update/app_update_service.dart 与
lib/domain/update/app_update.dart。

运行：python tool/test_update_parser.py
"""
import json
import re
from typing import Any, Dict, List, Optional, Tuple

# ---------------------------------------------------------------------------
# 以下逻辑与 Dart 端一一对应
# ---------------------------------------------------------------------------


def version_parts(version: str) -> List[int]:
    """去掉 v 前缀，按 . 分段转 int；非法时返回 [0]（对应 Dart _versionParts）。"""
    normalized = version.strip()
    normalized = re.sub(r"^[vV]", "", normalized)
    parts: List[int] = []
    for segment in normalized.split("."):
        try:
            parts.append(int(segment.strip()))
        except ValueError:
            return [0]
    return parts if parts else [0]


def compare_versions(a: str, b: str) -> int:
    """语义化比较，返回负数/零/正数（对应 Dart compareAppVersions）。"""
    pa, pb = version_parts(a), version_parts(b)
    length = max(len(pa), len(pb))
    for i in range(length):
        va = pa[i] if i < len(pa) else 0
        vb = pb[i] if i < len(pb) else 0
        if va != vb:
            return -1 if va < vb else 1
    return 0


def first_string(json_map: Dict[str, Any], keys: List[str]) -> Optional[str]:
    """按候选键取第一个非空字符串（对应 Dart _firstString）。"""
    for key in keys:
        value = json_map.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return None


def parse_version_config(body: str) -> Optional[Dict[str, Any]]:
    """解析 version.json；非法 JSON 或缺版本号返回 None（对应 Dart _parseVersionConfig）。"""
    try:
        decoded = json.loads(body)
    except Exception:
        return None
    if not isinstance(decoded, dict):
        return None

    tag_name = first_string(
        decoded, ["version", "latest_version", "tag_name", "latestVersion"]
    )
    if tag_name is None:
        return None
    version = re.sub(r"^[vV]", "", tag_name)
    try:
        int(version.split(".")[0])
    except ValueError:
        return None

    return {
        "tagName": tag_name,
        "version": version,
        "body": first_string(
            decoded,
            ["note", "changelog", "update_note", "release_notes", "body", "description"],
        )
        or "",
        "apkDownloadUrl": first_string(
            decoded,
            ["apk_url", "apkUrl", "download_url", "downloadUrl", "url", "apk",
             "apk_link", "apkLink"],
        ),
        "releasePageUrl": first_string(
            decoded,
            ["html_url", "page_url", "release_page", "homepage", "project_url"],
        )
        or "",
    }


def check_has_update(current: str, config: Optional[Dict[str, Any]]) -> Tuple[bool, str]:
    """模拟 AppUpdateCheckResult：最新版严格大于当前版才提示更新。"""
    if config is None:
        return False, "version.json 内容无法识别"
    return compare_versions(config["version"], current) > 0, ""

# ---------------------------------------------------------------------------
# 测试
# ---------------------------------------------------------------------------


def run() -> None:
    passed = 0
    failed = 0

    def assert_eq(name: str, actual: Any, expected: Any) -> None:
        nonlocal passed, failed
        if actual == expected:
            passed += 1
            print("PASS " + name)
        else:
            failed += 1
            print("FAIL " + name + " -> expected=" + repr(expected) + " actual=" + repr(actual))

    # --- 版本比较 ---
    assert_eq("compare 相同", compare_versions("1.0.0", "1.0.0"), 0)
    assert_eq("compare major 升", compare_versions("2.0.0", "1.0.0"), 1)
    assert_eq("compare minor 升", compare_versions("1.1.0", "1.0.0"), 1)
    assert_eq("compare patch 升", compare_versions("1.0.1", "1.0.0"), 1)
    assert_eq("compare 降", compare_versions("1.0.0", "1.0.1"), -1)
    assert_eq("compare v 前缀", compare_versions("v1.1.0", "1.0.0"), 1)
    assert_eq("compare v 前缀同", compare_versions("v1.0.0", "1.0.0"), 0)
    assert_eq("compare 缺段补 0", compare_versions("1.1", "1.1.0"), 0)
    assert_eq("compare 大段", compare_versions("2", "1.9.9"), 1)

    # --- 解析：标准字段 ---
    cfg = parse_version_config(
        json.dumps({
            "version": "v1.1.0",
            "note": "修复若干问题",
            "apk_url": "https://x/app.apk",
            "html_url": "https://gitee.com/eb-Dog/delicious-food",
        })
    )
    assert_eq("解析 标准字段 version", cfg["version"], "1.1.0")
    assert_eq("解析 标准字段 body", cfg["body"], "修复若干问题")
    assert_eq("解析 标准字段 apk", cfg["apkDownloadUrl"], "https://x/app.apk")
    assert_eq("解析 标准字段 page", cfg["releasePageUrl"], "https://gitee.com/eb-Dog/delicious-food")

    # --- 解析：宽容候选键 ---
    cfg2 = parse_version_config(
        json.dumps({
            "latest_version": "2.0.0",
            "changelog": "全新改版",
            "download_url": "https://x/v2.apk",
            "page_url": "https://gitee.com/eb-Dog/delicious-food",
        })
    )
    assert_eq("宽容 latest_version", cfg2["version"], "2.0.0")
    assert_eq("宽容 changelog", cfg2["body"], "全新改版")
    assert_eq("宽容 download_url", cfg2["apkDownloadUrl"], "https://x/v2.apk")
    assert_eq("宽容 page_url", cfg2["releasePageUrl"], "https://gitee.com/eb-Dog/delicious-food")

    # --- 解析：边界 ---
    assert_eq("缺版本号返回 None", parse_version_config('{"note": "x"}'), None)
    assert_eq("非法 JSON 返回 None", parse_version_config("not-json"), None)
    assert_eq("非对象返回 None", parse_version_config("[1,2]"), None)
    cfg3 = parse_version_config(json.dumps({"version": "1.2.3"}))
    assert_eq("仅版本号 body 空", cfg3["body"], "")
    assert_eq("仅版本号 apk None", cfg3["apkDownloadUrl"], None)
    assert_eq("v 前缀大写", parse_version_config(json.dumps({"version": "V3.0.0"}))["version"], "3.0.0")

    # --- 提示更新判定 ---
    cfg4 = parse_version_config(json.dumps({"version": "1.1.0", "note": "n"}))
    cfg_equal = parse_version_config(json.dumps({"version": "1.0.0"}))
    assert_eq("1.1.0 > 1.0.0 提示更新", check_has_update("1.0.0", cfg4)[0], True)
    assert_eq("1.0.0 == 1.0.0 不提示", check_has_update("1.0.0", cfg_equal)[0], False)
    assert_eq("解析失败不提示", check_has_update("1.0.0", None)[0], False)

    print("----")
    print("PASS=%d FAIL=%d" % (passed, failed))
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    run()
