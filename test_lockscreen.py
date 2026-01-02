# test_lockscreen.py
"""
锁屏状态下的 GUI 自动化可行性测试

这个脚本会测试在锁屏状态下：
1. 截图能否捕获桌面内容
2. 窗口句柄能否正常获取
3. PyAutoGUI 能否正常工作

使用方法：
1. 运行脚本
2. 在倒计时期间按 Win+L 锁定屏幕
3. 等待测试完成
4. 解锁后查看结果
"""

import time
import os
import json
from datetime import datetime
from pathlib import Path

# 测试结果输出目录
OUTPUT_DIR = Path("lockscreen_test_results")
OUTPUT_DIR.mkdir(exist_ok=True)


def test_1_screenshot():
    """
    测试 1: 锁屏状态下的截图
    
    验证 MSS 截图库在锁屏时能否捕获桌面内容
    """
    print("\n" + "=" * 60)
    print("测试 1: 截图测试")
    print("=" * 60)
    
    try:
        import mss
        from PIL import Image
        
        with mss.mss() as sct:
            # 截取主显示器
            monitor = sct.monitors[1]
            screenshot = sct.grab(monitor)
            
            # 转换为 PIL Image
            img = Image.frombytes("RGB", screenshot.size, screenshot.bgra, "raw", "BGRX")
            
            # 保存截图
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filepath = OUTPUT_DIR / f"screenshot_locked_{timestamp}.png"
            img.save(filepath)
            
            # 分析截图
            pixels = list(img.getdata())
            total_pixels = len(pixels)
            
            # 计算平均亮度
            avg_brightness = sum(sum(p) for p in pixels) / (total_pixels * 3)
            
            # 计算颜色多样性（简单方法：统计不同颜色数量）
            unique_colors = len(set(pixels[:10000]))  # 采样前 10000 个像素
            
            result = {
                "test": "screenshot",
                "success": True,
                "filepath": str(filepath),
                "resolution": f"{img.width}x{img.height}",
                "avg_brightness": round(avg_brightness, 2),
                "color_diversity": unique_colors,
                "analysis": ""
            }
            
            # 分析结果
            if avg_brightness < 30 and unique_colors < 100:
                result["analysis"] = "可能是黑屏或锁屏界面（亮度低，颜色单一）"
                result["likely_locked"] = True
            elif unique_colors < 500:
                result["analysis"] = "可能是锁屏界面（颜色较少）"
                result["likely_locked"] = True
            else:
                result["analysis"] = "可能捕获到了桌面内容（颜色丰富）"
                result["likely_locked"] = False
            
            print(f"  ✓ 截图已保存: {filepath}")
            print(f"  ✓ 分辨率: {result['resolution']}")
            print(f"  ✓ 平均亮度: {result['avg_brightness']}")
            print(f"  ✓ 颜色多样性: {result['color_diversity']}")
            print(f"  → 分析: {result['analysis']}")
            
            return result
            
    except Exception as e:
        print(f"  ✗ 截图失败: {e}")
        return {"test": "screenshot", "success": False, "error": str(e)}


def test_2_window_enumeration():
    """
    测试 2: 窗口枚举
    
    验证在锁屏状态下能否获取窗口列表
    """
    print("\n" + "=" * 60)
    print("测试 2: 窗口枚举测试")
    print("=" * 60)
    
    try:
        import win32gui
        import win32process
        
        windows = []
        
        def enum_callback(hwnd, results):
            if win32gui.IsWindowVisible(hwnd):
                title = win32gui.GetWindowText(hwnd)
                if title:  # 只记录有标题的窗口
                    try:
                        _, pid = win32process.GetWindowThreadProcessId(hwnd)
                        rect = win32gui.GetWindowRect(hwnd)
                        results.append({
                            "hwnd": hwnd,
                            "title": title[:50],  # 截断长标题
                            "pid": pid,
                            "rect": rect
                        })
                    except:
                        pass
            return True
        
        win32gui.EnumWindows(enum_callback, windows)
        
        result = {
            "test": "window_enumeration",
            "success": True,
            "window_count": len(windows),
            "windows": windows[:20]  # 只保存前 20 个
        }
        
        print(f"  ✓ 找到 {len(windows)} 个可见窗口")
        print(f"  ✓ 部分窗口列表:")
        for w in windows[:10]:
            print(f"      - [{w['hwnd']}] {w['title']}")
        
        # 检查是否能找到特定窗口（比如 explorer）
        explorer_found = any("explorer" in w["title"].lower() or "任务栏" in w["title"] for w in windows)
        result["explorer_found"] = explorer_found
        
        if explorer_found:
            print(f"  ✓ 检测到 Explorer 相关窗口")
        else:
            print(f"  ⚠ 未检测到 Explorer 相关窗口")
        
        return result
        
    except Exception as e:
        print(f"  ✗ 窗口枚举失败: {e}")
        return {"test": "window_enumeration", "success": False, "error": str(e)}


def test_3_find_specific_window():
    """
    测试 3: 查找特定窗口
    
    尝试查找 Comet 浏览器窗口（如果正在运行）
    """
    print("\n" + "=" * 60)
    print("测试 3: 查找特定窗口")
    print("=" * 60)
    
    try:
        import win32gui
        
        # 搜索关键词
        keywords = ["Comet", "Chrome", "Edge", "Firefox", "Notepad", "记事本"]
        found_windows = {}
        
        def enum_callback(hwnd, results):
            if win32gui.IsWindowVisible(hwnd):
                title = win32gui.GetWindowText(hwnd)
                for kw in keywords:
                    if kw.lower() in title.lower():
                        if kw not in results:
                            results[kw] = []
                        results[kw].append({
                            "hwnd": hwnd,
                            "title": title[:80]
                        })
            return True
        
        win32gui.EnumWindows(enum_callback, found_windows)
        
        result = {
            "test": "find_specific_window",
            "success": True,
            "searched_keywords": keywords,
            "found": found_windows
        }
        
        if found_windows:
            print(f"  ✓ 找到以下窗口:")
            for kw, wins in found_windows.items():
                for w in wins:
                    print(f"      - [{kw}] {w['title']}")
        else:
            print(f"  ⚠ 未找到任何目标窗口")
            print(f"      搜索关键词: {keywords}")
        
        return result
        
    except Exception as e:
        print(f"  ✗ 查找窗口失败: {e}")
        return {"test": "find_specific_window", "success": False, "error": str(e)}


def test_4_mouse_position():
    """
    测试 4: 鼠标位置
    
    验证能否获取和设置鼠标位置
    """
    print("\n" + "=" * 60)
    print("测试 4: 鼠标位置测试")
    print("=" * 60)
    
    try:
        import pyautogui
        
        # 获取当前位置
        original_pos = pyautogui.position()
        print(f"  ✓ 当前鼠标位置: {original_pos}")
        
        # 获取屏幕尺寸
        screen_size = pyautogui.size()
        print(f"  ✓ 屏幕尺寸: {screen_size}")
        
        # 尝试移动鼠标到屏幕中心
        center = (screen_size[0] // 2, screen_size[1] // 2)
        pyautogui.moveTo(center[0], center[1], duration=0.1)
        
        # 验证移动
        new_pos = pyautogui.position()
        move_success = abs(new_pos[0] - center[0]) < 10 and abs(new_pos[1] - center[1]) < 10
        
        # 恢复原位置
        pyautogui.moveTo(original_pos[0], original_pos[1], duration=0.1)
        
        result = {
            "test": "mouse_position",
            "success": True,
            "original_position": original_pos,
            "screen_size": screen_size,
            "move_target": center,
            "move_result": new_pos,
            "move_success": move_success
        }
        
        if move_success:
            print(f"  ✓ 鼠标移动成功: {original_pos} → {new_pos}")
        else:
            print(f"  ⚠ 鼠标移动可能失败: 目标 {center}, 实际 {new_pos}")
        
        return result
        
    except Exception as e:
        print(f"  ✗ 鼠标测试失败: {e}")
        return {"test": "mouse_position", "success": False, "error": str(e)}


def test_5_keyboard():
    """
    测试 5: 键盘输入
    
    验证键盘状态（不实际发送按键，避免干扰锁屏）
    """
    print("\n" + "=" * 60)
    print("测试 5: 键盘状态测试")
    print("=" * 60)
    
    try:
        import pyautogui
        import ctypes
        
        # 检查 Caps Lock 状态
        VK_CAPITAL = 0x14
        caps_lock = ctypes.windll.user32.GetKeyState(VK_CAPITAL) & 1
        
        # 检查 Num Lock 状态
        VK_NUMLOCK = 0x90
        num_lock = ctypes.windll.user32.GetKeyState(VK_NUMLOCK) & 1
        
        result = {
            "test": "keyboard",
            "success": True,
            "caps_lock": bool(caps_lock),
            "num_lock": bool(num_lock),
            "note": "未发送实际按键，避免干扰锁屏密码输入"
        }
        
        print(f"  ✓ Caps Lock: {'开启' if caps_lock else '关闭'}")
        print(f"  ✓ Num Lock: {'开启' if num_lock else '关闭'}")
        print(f"  ℹ 注意: 未发送实际按键")
        
        return result
        
    except Exception as e:
        print(f"  ✗ 键盘测试失败: {e}")
        return {"test": "keyboard", "success": False, "error": str(e)}


def test_6_process_check():
    """
    测试 6: 进程检查
    
    验证能否访问进程信息
    """
    print("\n" + "=" * 60)
    print("测试 6: 进程检查")
    print("=" * 60)
    
    try:
        import psutil
        
        # 查找关键进程
        target_processes = ["explorer.exe", "dwm.exe", "LogonUI.exe", "comet.exe", "chrome.exe"]
        found_processes = {}
        
        for proc in psutil.process_iter(['pid', 'name', 'status']):
            try:
                name = proc.info['name'].lower()
                for target in target_processes:
                    if target.lower() in name:
                        if target not in found_processes:
                            found_processes[target] = []
                        found_processes[target].append({
                            "pid": proc.info['pid'],
                            "name": proc.info['name'],
                            "status": proc.info['status']
                        })
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                pass
        
        result = {
            "test": "process_check",
            "success": True,
            "searched_processes": target_processes,
            "found": found_processes
        }
        
        print(f"  ✓ 进程检查结果:")
        for target in target_processes:
            if target in found_processes:
                procs = found_processes[target]
                print(f"      ✓ {target}: {len(procs)} 个实例运行中")
            else:
                print(f"      - {target}: 未运行")
        
        # 特别检查 LogonUI.exe（锁屏界面进程）
        if "LogonUI.exe" in found_processes:
            print(f"\n  ⚠ 检测到 LogonUI.exe - 确认屏幕已锁定")
            result["screen_locked"] = True
        else:
            print(f"\n  ℹ 未检测到 LogonUI.exe - 屏幕可能未锁定")
            result["screen_locked"] = False
        
        return result
        
    except Exception as e:
        print(f"  ✗ 进程检查失败: {e}")
        return {"test": "process_check", "success": False, "error": str(e)}


def run_all_tests(delay_seconds=15):
    """
    运行所有测试
    
    Args:
        delay_seconds: 锁屏前的等待时间
    """
    print("=" * 60)
    print("  锁屏状态 GUI 自动化可行性测试")
    print("=" * 60)
    print()
    print(f"⏰ 请在 {delay_seconds} 秒内按 Win+L 锁定屏幕")
    print()
    print("测试将在锁屏状态下执行以下检查:")
    print("  1. 截图测试 - 验证能否捕获桌面内容")
    print("  2. 窗口枚举 - 验证能否获取窗口列表")
    print("  3. 查找窗口 - 验证能否找到特定窗口")
    print("  4. 鼠标测试 - 验证能否控制鼠标")
    print("  5. 键盘测试 - 验证键盘状态")
    print("  6. 进程检查 - 验证进程访问")
    print()
    
    # 倒计时
    for i in range(delay_seconds, 0, -1):
        print(f"\r  倒计时: {i:2d} 秒 - 请现在锁定屏幕 (Win+L)", end="", flush=True)
        time.sleep(1)
    
    print("\n")
    print("🔒 开始测试（假设屏幕已锁定）...")
    print()
    
    # 运行所有测试
    results = {
        "timestamp": datetime.now().isoformat(),
        "tests": []
    }
    
    results["tests"].append(test_1_screenshot())
    results["tests"].append(test_2_window_enumeration())
    results["tests"].append(test_3_find_specific_window())
    results["tests"].append(test_4_mouse_position())
    results["tests"].append(test_5_keyboard())
    results["tests"].append(test_6_process_check())
    
    # 保存结果
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    result_file = OUTPUT_DIR / f"test_results_{timestamp}.json"
    
    with open(result_file, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2, ensure_ascii=False, default=str)
    
    # 打印总结
    print("\n")
    print("=" * 60)
    print("  测试总结")
    print("=" * 60)
    print()
    
    all_success = True
    for test in results["tests"]:
        status = "✓" if test.get("success") else "✗"
        print(f"  {status} {test['test']}")
        if not test.get("success"):
            all_success = False
    
    print()
    print(f"  📁 结果保存至: {OUTPUT_DIR.absolute()}")
    print(f"  📄 JSON 报告: {result_file.name}")
    print()
    
    # 最终结论
    print("=" * 60)
    print("  结论")
    print("=" * 60)
    print()
    
    # 检查关键指标
    screenshot_test = next((t for t in results["tests"] if t["test"] == "screenshot"), {})
    process_test = next((t for t in results["tests"] if t["test"] == "process_check"), {})
    
    screen_locked = process_test.get("screen_locked", False)
    likely_locked_screenshot = screenshot_test.get("likely_locked", True)
    
    if screen_locked:
        print("  🔒 确认: 屏幕处于锁定状态 (检测到 LogonUI.exe)")
        print()
        
        if likely_locked_screenshot:
            print("  ❌ 结论: 锁屏状态下无法进行 GUI 自动化")
            print()
            print("  原因: 截图捕获的是锁屏界面，不是桌面内容")
            print("  建议: 执行自动化任务前需要先解锁屏幕")
        else:
            print("  ⚠️ 异常: 截图似乎捕获到了桌面内容")
            print()
            print("  这可能是误判，请手动查看截图文件确认")
    else:
        print("  🔓 屏幕未锁定或检测失败")
        print()
        print("  请确保在倒计时期间按 Win+L 锁定了屏幕")
        print("  如果确实锁定了，可能是检测方法不够准确")
    
    print()
    print("  📸 请查看截图文件以最终确认测试结果")
    print(f"     {OUTPUT_DIR.absolute()}")
    print()
    
    return results


if __name__ == "__main__":
    import sys
    
    # 检查依赖
    required_packages = ["mss", "Pillow", "pyautogui", "psutil", "pywin32"]
    missing = []
    
    try:
        import mss
    except ImportError:
        missing.append("mss")
    
    try:
        from PIL import Image
    except ImportError:
        missing.append("Pillow")
    
    try:
        import pyautogui
    except ImportError:
        missing.append("pyautogui")
    
    try:
        import psutil
    except ImportError:
        missing.append("psutil")
    
    try:
        import win32gui
    except ImportError:
        missing.append("pywin32")
    
    if missing:
        print("缺少依赖包，请先安装:")
        print(f"  pip install {' '.join(missing)}")
        sys.exit(1)
    
    # 运行测试
    # 可以通过命令行参数调整等待时间
    delay = int(sys.argv[1]) if len(sys.argv) > 1 else 15
    
    run_all_tests(delay_seconds=delay)
