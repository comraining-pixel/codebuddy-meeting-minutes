#!/usr/bin/env python3
"""
Meeting Minutes Skill — 图片 OCR 文字提取脚本

支持多级降级：
  Level 1: macOS Vision Framework (pyobjc) — 中英文识别最优
  Level 2: Tesseract OCR CLI — 广泛兼容
  Level 3: 输出错误提示，建议手动粘贴

用法:
    python3 ocr.py <图片路径> [图片路径2 ...]
    python3 ocr.py --method vision image.png
    python3 ocr.py --method tesseract image.png

输出: 提取的纯文本到 stdout
"""

import sys
import os
import subprocess
import platform
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent.resolve()
VENV_PYTHON = SCRIPT_DIR / ".venv" / "bin" / "python3"


def get_macos_version():
    """获取 macOS 主版本号，非 macOS 返回 0"""
    if platform.system() != "Darwin":
        return 0
    try:
        ver = platform.mac_ver()[0]
        return int(ver.split(".")[0])
    except (ValueError, IndexError):
        return 0


def ensure_venv():
    """确保 venv 存在且 pyobjc 已安装，返回 venv python 路径或 None"""
    if VENV_PYTHON.exists():
        # 测试 import
        result = subprocess.run(
            [str(VENV_PYTHON), "-c", "import Vision; import Quartz"],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            return str(VENV_PYTHON)

    # 尝试创建 venv 并安装
    venv_dir = SCRIPT_DIR / ".venv"
    try:
        # 优先用 uv
        if subprocess.run(["uv", "--version"], capture_output=True).returncode == 0:
            subprocess.run(["uv", "venv", str(venv_dir), "--python", "python3"],
                           capture_output=True, check=True)
            subprocess.run(["uv", "pip", "install", "--python", str(VENV_PYTHON),
                            "pyobjc-framework-Vision", "pyobjc-framework-Quartz"],
                           capture_output=True, check=True)
        else:
            import venv
            venv.create(str(venv_dir), with_pip=True)
            subprocess.run([str(VENV_PYTHON.parent / "pip3"), "install",
                            "pyobjc-framework-Vision", "pyobjc-framework-Quartz"],
                           capture_output=True, check=True)

        return str(VENV_PYTHON) if VENV_PYTHON.exists() else None
    except Exception as e:
        print(f"⚠️ pyobjc 安装失败: {e}", file=sys.stderr)
        return None


def ocr_vision(image_path: str) -> str:
    """使用 macOS Vision Framework 进行 OCR（通过子进程调用 venv python）"""
    venv_py = ensure_venv()
    if not venv_py:
        raise RuntimeError("Vision Framework pyobjc 环境不可用")

    # 通过子进程执行 Vision OCR，避免主进程 import 问题
    vision_script = '''
import sys
import Quartz
from Foundation import NSURL
import Vision

def ocr_image(path):
    url = NSURL.fileURLWithPath_(path)
    ci_image = Quartz.CIImage.imageWithContentsOfURL_(url)
    if ci_image is None:
        print(f"错误: 无法加载图片 {path}", file=sys.stderr)
        return ""

    handler = Vision.VNImageRequestHandler.alloc().initWithCIImage_options_(ci_image, None)
    request = Vision.VNRecognizeTextRequest.alloc().init()
    request.setRecognitionLevel_(Vision.VNRequestTextRecognitionLevelAccurate)
    request.setRecognitionLanguages_(["zh-Hans", "zh-Hant", "en"])
    request.setUsesLanguageCorrection_(True)

    success = handler.performRequests_error_([request], None)
    if not success[0]:
        print(f"错误: OCR 请求失败", file=sys.stderr)
        return ""

    results = request.results()
    lines = []
    for observation in results:
        candidate = observation.topCandidates_(1)
        if candidate:
            lines.append(candidate[0].string())
    return "\\n".join(lines)

path = sys.argv[1]
text = ocr_image(path)
print(text)
'''
    result = subprocess.run(
        [venv_py, "-c", vision_script, image_path],
        capture_output=True, text=True, timeout=120
    )
    if result.returncode != 0:
        raise RuntimeError(f"Vision OCR 失败: {result.stderr}")
    return result.stdout.strip()


def ocr_tesseract(image_path: str) -> str:
    """使用 Tesseract OCR CLI"""
    # 检查 tesseract 是否可用
    if subprocess.run(["tesseract", "--version"], capture_output=True).returncode != 0:
        raise RuntimeError("tesseract 未安装")

    result = subprocess.run(
        ["tesseract", image_path, "stdout", "-l", "chi_sim+chi_tra+eng"],
        capture_output=True, text=True, timeout=120
    )
    if result.returncode != 0:
        # 降级到仅英文
        result = subprocess.run(
            ["tesseract", image_path, "stdout"],
            capture_output=True, text=True, timeout=120
        )
    if result.returncode != 0:
        raise RuntimeError(f"Tesseract OCR 失败: {result.stderr}")
    return result.stdout.strip()


def ocr_image(image_path: str, method: str = "auto") -> str:
    """
    对图片进行 OCR，支持自动降级
    method: auto | vision | tesseract
    """
    path = Path(image_path)
    if not path.exists():
        print(f"❌ 文件不存在: {image_path}", file=sys.stderr)
        return ""

    # 检查文件是否为支持的图片格式
    supported = {".jpg", ".jpeg", ".png", ".bmp", ".tiff", ".tif", ".gif", ".webp", ".heic", ".heif", ".pdf"}
    if path.suffix.lower() not in supported:
        print(f"⚠️ 不支持的图片格式: {path.suffix}", file=sys.stderr)
        return ""

    errors = []

    # Level 1: Vision Framework
    if method in ("auto", "vision"):
        macos_ver = get_macos_version()
        if macos_ver >= 12:
            try:
                text = ocr_vision(image_path)
                if text:
                    return text
                errors.append("Vision OCR 返回空结果")
            except Exception as e:
                errors.append(f"Vision OCR: {e}")
        elif method == "vision":
            errors.append(f"Vision Framework 需要 macOS 12+，当前版本: {macos_ver}")

    # Level 2: Tesseract
    if method in ("auto", "tesseract"):
        try:
            text = ocr_tesseract(image_path)
            if text:
                return text
            errors.append("Tesseract OCR 返回空结果")
        except Exception as e:
            errors.append(f"Tesseract: {e}")

    # Level 3: 兜底提示
    if errors:
        print(f"⚠️ OCR 降级链全部失败:", file=sys.stderr)
        for err in errors:
            print(f"   - {err}", file=sys.stderr)
    print("💡 请手动将图片中的文字内容粘贴到对话中", file=sys.stderr)
    return ""


def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print("用法: python3 ocr.py [--method vision|tesseract|auto] <图片路径> [图片路径2 ...]")
        print("\n支持格式: jpg, jpeg, png, bmp, tiff, gif, webp, heic, pdf")
        print("\n降级策略:")
        print("  1. macOS Vision Framework (pyobjc) — 最优中英文识别")
        print("  2. Tesseract OCR — 广泛兼容")
        print("  3. 提示手动粘贴 — 兜底")
        sys.exit(0)

    # 解析参数
    method = "auto"
    image_paths = []

    i = 1
    while i < len(sys.argv):
        if sys.argv[i] == "--method" and i + 1 < len(sys.argv):
            method = sys.argv[i + 1]
            i += 2
        else:
            image_paths.append(sys.argv[i])
            i += 1

    if not image_paths:
        print("❌ 请提供至少一个图片路径", file=sys.stderr)
        sys.exit(1)

    # 处理每个图片
    all_text = []
    for img_path in image_paths:
        print(f"📷 处理: {img_path}", file=sys.stderr)
        text = ocr_image(img_path, method)
        if text:
            if len(image_paths) > 1:
                all_text.append(f"--- {Path(img_path).name} ---")
            all_text.append(text)

    # 输出合并结果到 stdout
    if all_text:
        print("\n".join(all_text))
    else:
        sys.exit(1)


if __name__ == "__main__":
    main()
