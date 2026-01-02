# test_auto_unlock.py
"""
Windows 自动解锁测试脚本

⚠️ 重要发现（2026-01-01）：
==================================
经过测试，Windows 锁屏使用的是 "Secure Desktop"（安全桌面），
这是一个完全隔离的会话（Session 0），与用户应用程序运行的会话（Session 1）分离。

这意味着：
1. PyAutoGUI 的 SendInput 无法发送按键到锁屏界面
2. 即使使用底层 ctypes + user32.SendInput 也无法穿透
3. 这是 Windows 的安全设计，防止恶意软件冒充锁屏

✅ 替代方案：
==================================
方案 1: 禁用安全桌面（适用于受信任环境）
   - 运行 secpol.msc
   - 导航到：本地策略 > 安全选项
   - 禁用："用户账户控制: 在安全桌面上运行提升"
   
方案 2: 使用 Windows 自动登录
   - 运行 netplwiz
   - 取消勾选 "要使用本计算机，用户必须输入用户名和密码"
   
方案 3: 使用计划任务在登录时运行
   - 创建计划任务，在用户登录时自动运行你的脚本
   
方案 4: 使用 Windows 服务（需要更多权限）
   - 创建一个 Windows 服务运行在 Session 0
   - 服务可以使用 WTSQueryUserToken + CreateProcessAsUser

此脚本保留作为参考，演示在**非锁屏**状态下的 SendInput 用法。
"""


import time
import sys
from datetime import datetime

# ============================================================================
# 配置区域 - 请修改这里
# ============================================================================

UNLOCK_PASSWORD = "980214"  # ← 改成你的 Windows 密码

COUNTDOWN_SECONDS = 10  # 锁屏前的倒计时秒数
UNLOCK_DELAY = 3        # 锁屏后等待几秒再开始解锁
KEY_INTERVAL = 0.05     # 按键之间的间隔（秒）

# ============================================================================


def check_dependencies():
    """检查依赖"""
    missing = []
    
    try:
        import pyautogui
    except ImportError:
        missing.append("pyautogui")
    
    try:
        import psutil
    except ImportError:
        missing.append("psutil")
    
    if missing:
        print(f"❌ 缺少依赖: {', '.join(missing)}")
        print(f"   请运行: pip install {' '.join(missing)}")
        return False
    
    return True


def is_screen_locked():
    """
    检测屏幕是否锁定
    
    通过检查 LogonUI.exe 进程是否运行来判断
    """
    try:
        import psutil
        
        for proc in psutil.process_iter(['name']):
            try:
                if proc.info['name'].lower() == 'logonui.exe':
                    return True
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                pass
        
        return False
    except Exception as e:
        print(f"⚠️ 无法检测锁屏状态: {e}")
        return None


def unlock_screen(password: str, verbose: bool = True):
    """
    自动解锁屏幕
    
    使用 Windows SendInput API 发送硬件级别的键盘输入
    这可以穿透 Secure Desktop（锁屏界面）
    
    Args:
        password: Windows 登录密码
        verbose: 是否打印详细信息
    
    Returns:
        bool: 是否成功执行解锁序列
    """
    import ctypes
    from ctypes import wintypes
    
    # ============================================================================
    # Windows SendInput API 定义
    # ============================================================================
    
    # 输入类型
    INPUT_KEYBOARD = 1
    
    # 键盘事件标志
    KEYEVENTF_KEYUP = 0x0002
    KEYEVENTF_UNICODE = 0x0004
    
    # 虚拟键码映射
    VK_CODES = {
        'enter': 0x0D,
        'space': 0x20,
        'backspace': 0x08,
        'esc': 0x1B,
        'shift': 0x10,
        'tab': 0x09,
        '0': 0x30, '1': 0x31, '2': 0x32, '3': 0x33, '4': 0x34,
        '5': 0x35, '6': 0x36, '7': 0x37, '8': 0x38, '9': 0x39,
        'a': 0x41, 'b': 0x42, 'c': 0x43, 'd': 0x44, 'e': 0x45,
        'f': 0x46, 'g': 0x47, 'h': 0x48, 'i': 0x49, 'j': 0x4A,
        'k': 0x4B, 'l': 0x4C, 'm': 0x4D, 'n': 0x4E, 'o': 0x4F,
        'p': 0x50, 'q': 0x51, 'r': 0x52, 's': 0x53, 't': 0x54,
        'u': 0x55, 'v': 0x56, 'w': 0x57, 'x': 0x58, 'y': 0x59,
        'z': 0x5A,
    }
    
    # 结构体定义
    class KEYBDINPUT(ctypes.Structure):
        _fields_ = [
            ('wVk', wintypes.WORD),
            ('wScan', wintypes.WORD),
            ('dwFlags', wintypes.DWORD),
            ('time', wintypes.DWORD),
            ('dwExtraInfo', ctypes.POINTER(ctypes.c_ulong)),
        ]
    
    class INPUT(ctypes.Structure):
        class _INPUT_UNION(ctypes.Union):
            _fields_ = [('ki', KEYBDINPUT)]
        _anonymous_ = ('_input',)
        _fields_ = [
            ('type', wintypes.DWORD),
            ('_input', _INPUT_UNION),
        ]
    
    def send_key(vk_code: int, key_up: bool = False):
        """发送单个按键"""
        inp = INPUT()
        inp.type = INPUT_KEYBOARD
        inp.ki.wVk = vk_code
        inp.ki.dwFlags = KEYEVENTF_KEYUP if key_up else 0
        ctypes.windll.user32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(INPUT))
    
    def press_key(vk_code: int):
        """按下并释放按键"""
        send_key(vk_code, False)  # 按下
        time.sleep(0.02)
        send_key(vk_code, True)   # 释放
        time.sleep(KEY_INTERVAL)
    
    def type_char(char: str):
        """输入单个字符（支持 Unicode）"""
        inp = INPUT()
        inp.type = INPUT_KEYBOARD
        inp.ki.wVk = 0
        inp.ki.wScan = ord(char)
        inp.ki.dwFlags = KEYEVENTF_UNICODE
        ctypes.windll.user32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(INPUT))
        time.sleep(0.02)
        
        # 释放
        inp.ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP
        ctypes.windll.user32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(INPUT))
        time.sleep(KEY_INTERVAL)
    
    def type_string(text: str):
        """输入字符串"""
        for char in text:
            lower_char = char.lower()
            if lower_char in VK_CODES:
                # 使用虚拟键码（更可靠）
                press_key(VK_CODES[lower_char])
            else:
                # 使用 Unicode 输入
                type_char(char)
    
    # ============================================================================
    # 解锁流程
    # ============================================================================
    
    try:
        if verbose:
            print("\n🔓 开始解锁序列（使用 Windows SendInput API）...")
        
        # Step 1: 唤醒屏幕
        if verbose:
            print("   [1/5] 唤醒屏幕...")
        
        # 移动鼠标唤醒（可选，有些系统需要）
        try:
            import pyautogui
            pyautogui.FAILSAFE = False
            pyautogui.move(10, 0)
            pyautogui.move(-10, 0)
        except:
            pass
        
        # 按 ESC 唤醒
        press_key(VK_CODES['esc'])
        time.sleep(0.5)
        
        # Step 2: 再次按键确保唤醒
        if verbose:
            print("   [2/5] 激活屏幕...")
        press_key(VK_CODES['space'])
        time.sleep(0.8)
        
        # Step 3: 显示密码输入框
        if verbose:
            print("   [3/5] 显示密码输入框...")
        # 按 Enter 或 Space 显示密码框
        press_key(VK_CODES['enter'])
        time.sleep(0.5)
        
        # Step 4: 清空并输入密码
        if verbose:
            print(f"   [4/5] 输入密码 ({'*' * len(password)})...")
        
        # 先清空可能已有的输入
        for _ in range(5):
            press_key(VK_CODES['backspace'])
        time.sleep(0.1)
        
        # 输入密码
        type_string(password)
        time.sleep(0.3)
        
        # Step 5: 按回车确认
        if verbose:
            print("   [5/5] 按回车确认...")
        press_key(VK_CODES['enter'])
        
        if verbose:
            print("\n✅ 解锁序列执行完成！")
        
        return True
        
    except Exception as e:
        print(f"\n❌ 解锁失败: {e}")
        import traceback
        traceback.print_exc()
        return False


def verify_unlocked(timeout: int = 5):
    """
    验证是否成功解锁
    
    Args:
        timeout: 最多等待几秒
    
    Returns:
        bool: 是否解锁成功
    """
    print(f"\n⏳ 验证解锁结果（等待 {timeout} 秒）...")
    
    start_time = time.time()
    
    while time.time() - start_time < timeout:
        if not is_screen_locked():
            return True
        time.sleep(0.5)
    
    return False


def run_unlock_test():
    """运行完整的解锁测试"""
    
    print("=" * 60)
    print("  Windows 自动解锁测试")
    print("=" * 60)
    print()
    
    # 检查密码是否已配置
    if UNLOCK_PASSWORD == "your_password_here":
        print("❌ 错误: 请先修改脚本中的 UNLOCK_PASSWORD")
        print("   打开 test_auto_unlock.py 并设置你的密码")
        return False
    
    print(f"📋 测试配置:")
    print(f"   - 密码长度: {len(UNLOCK_PASSWORD)} 字符")
    print(f"   - 倒计时: {COUNTDOWN_SECONDS} 秒")
    print(f"   - 解锁延迟: {UNLOCK_DELAY} 秒")
    print()
    
    # 检查当前是否已锁屏
    current_locked = is_screen_locked()
    if current_locked:
        print("⚠️ 检测到屏幕已经锁定！")
        print("   将直接尝试解锁...")
        print()
    else:
        print(f"🔒 请在 {COUNTDOWN_SECONDS} 秒内按 Win+L 锁定屏幕")
        print()
        
        # 倒计时
        for i in range(COUNTDOWN_SECONDS, 0, -1):
            # 检查是否已经锁屏
            if is_screen_locked():
                print(f"\r✓ 检测到屏幕已锁定！                    ")
                break
            print(f"\r   倒计时: {i:2d} 秒 - 现在按 Win+L 锁定屏幕", end="", flush=True)
            time.sleep(1)
        
        print()
    
    # 确认锁屏状态
    if not is_screen_locked():
        print("\n⚠️ 屏幕似乎没有锁定")
        print("   继续执行解锁序列（可能不会有效果）...")
    else:
        print(f"\n🔒 屏幕已锁定，{UNLOCK_DELAY} 秒后开始解锁...")
        time.sleep(UNLOCK_DELAY)
    
    # 执行解锁
    success = unlock_screen(UNLOCK_PASSWORD)
    
    if not success:
        return False
    
    # 验证结果
    time.sleep(2)  # 等待系统响应
    
    unlocked = verify_unlocked(timeout=5)
    
    print()
    print("=" * 60)
    print("  测试结果")
    print("=" * 60)
    print()
    
    if unlocked:
        print("✅ 成功！屏幕已解锁")
        print()
        print("📝 下一步:")
        print("   1. 可以将此功能集成到 Comet TaskRunner API")
        print("   2. 创建 /system/unlock 端点")
        return True
    else:
        locked_still = is_screen_locked()
        if locked_still:
            print("❌ 失败！屏幕仍然锁定")
            print()
            print("可能的原因:")
            print("   1. 密码不正确")
            print("   2. 需要点击用户头像")
            print("   3. 锁屏界面布局不同")
            print()
            print("建议:")
            print("   1. 确认密码正确")
            print("   2. 尝试增加 UNLOCK_DELAY")
            print("   3. 手动解锁后查看锁屏界面布局")
        else:
            print("⚠️ 状态不确定")
            print("   LogonUI.exe 未检测到，但验证超时")
        
        return False


def run_quick_unlock():
    """
    快速解锁模式 - 不等待，直接解锁
    
    用于已经锁屏的情况下直接调用
    """
    print("🔓 快速解锁模式")
    print()
    
    if UNLOCK_PASSWORD == "your_password_here":
        print("❌ 错误: 请先修改脚本中的 UNLOCK_PASSWORD")
        return False
    
    # 检查是否锁屏
    if not is_screen_locked():
        print("ℹ️ 屏幕未锁定，无需解锁")
        return True
    
    print("🔒 检测到锁屏，开始解锁...")
    
    success = unlock_screen(UNLOCK_PASSWORD)
    
    time.sleep(2)
    
    if not is_screen_locked():
        print("✅ 解锁成功！")
        return True
    else:
        print("❌ 解锁失败")
        return False


# ============================================================================
# 高级解锁方法（备选）
# ============================================================================

def unlock_screen_advanced(password: str):
    """
    高级解锁方法
    
    针对某些特殊情况的解锁流程
    """
    import pyautogui
    
    print("\n🔓 高级解锁序列...")
    
    try:
        # 方法 1: 模拟 Ctrl+Alt+Del（某些企业环境需要）
        # pyautogui.hotkey('ctrl', 'alt', 'delete')
        # time.sleep(1)
        
        # 方法 2: 移动鼠标唤醒
        print("   [1/6] 移动鼠标唤醒...")
        screen_width, screen_height = pyautogui.size()
        pyautogui.moveTo(screen_width // 2, screen_height // 2)
        pyautogui.move(100, 0)
        pyautogui.move(-100, 0)
        time.sleep(1)
        
        # 方法 3: 按 ESC 关闭可能的提示
        print("   [2/6] 按 ESC...")
        pyautogui.press('escape')
        time.sleep(0.3)
        
        # 方法 4: 按空格显示密码框
        print("   [3/6] 按空格...")
        pyautogui.press('space')
        time.sleep(0.5)
        
        # 方法 5: 点击屏幕下半部分（密码框通常在这里）
        print("   [4/6] 点击密码区域...")
        pyautogui.click(screen_width // 2, int(screen_height * 0.6))
        time.sleep(0.5)
        
        # 方法 6: 输入密码
        print(f"   [5/6] 输入密码...")
        pyautogui.typewrite(password, interval=0.08)
        time.sleep(0.3)
        
        # 方法 7: 回车
        print("   [6/6] 确认...")
        pyautogui.press('enter')
        
        print("\n✅ 高级解锁序列完成")
        return True
        
    except Exception as e:
        print(f"\n❌ 高级解锁失败: {e}")
        return False


# ============================================================================
# 主程序
# ============================================================================

if __name__ == "__main__":
    # 检查依赖
    if not check_dependencies():
        sys.exit(1)
    
    # 解析命令行参数
    if len(sys.argv) > 1:
        if sys.argv[1] == "--quick" or sys.argv[1] == "-q":
            # 快速模式：直接解锁，不倒计时
            run_quick_unlock()
        elif sys.argv[1] == "--advanced" or sys.argv[1] == "-a":
            # 高级模式
            if UNLOCK_PASSWORD != "your_password_here":
                unlock_screen_advanced(UNLOCK_PASSWORD)
            else:
                print("❌ 请先设置密码")
        elif sys.argv[1] == "--help" or sys.argv[1] == "-h":
            print("用法:")
            print("  python test_auto_unlock.py          # 完整测试（带倒计时）")
            print("  python test_auto_unlock.py -q       # 快速解锁（直接执行）")
            print("  python test_auto_unlock.py -a       # 高级解锁方法")
            print()
            print("配置:")
            print("  修改脚本开头的 UNLOCK_PASSWORD 变量")
        else:
            print(f"未知参数: {sys.argv[1]}")
            print("使用 --help 查看帮助")
    else:
        # 默认：完整测试
        run_unlock_test()
