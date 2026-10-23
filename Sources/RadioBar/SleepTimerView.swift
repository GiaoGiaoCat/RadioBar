import SwiftUI

@MainActor
struct SleepTimerControls: View {
    @ObservedObject var timer: SleepTimer
    @ObservedObject var settings: AppSettings
    private func text(_ zh: String, _ en: String) -> String { settings.text(zh, en) }
    private var phase: String {
        timer.isRunning ? text("计时中", "Active") : timer.isFadingOut ? text("正在渐弱停止", "Fading out")
            : timer.hasExpired ? text("已结束", "Finished") : text("未开启", "Off")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard {
                HStack {
                    SettingsRowTitle(title: text("睡眠定时", "Sleep timer"),
                                     subtitle: text("倒计时结束后，声音在 6 秒内平缓渐弱停止。", "Gently fade out over 6 seconds when the countdown ends."),
                                     titleWeight: .medium)
                    Spacer(minLength: 8)
                    Text(phase).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize()
                }

                HStack(alignment: .center, spacing: 8) {
                    Text(text("播放时长", "Play for")).font(.system(size: 13)).fixedSize()
                    Spacer(minLength: 16)
                    TextField("", text: $timer.minutesInput)
                        .labelsHidden().textFieldStyle(.roundedBorder).controlSize(.regular)
                        .font(.system(size: 17, weight: .regular).monospacedDigit())
                        .multilineTextAlignment(.trailing).frame(width: 60, height: 30)
                        .accessibilityIdentifier("sleepTimerMinutes")
                        .accessibilityLabel(text("倒计时分钟数", "Countdown in minutes"))
                    Text(text("分钟", "min")).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize()
                }

                HStack(spacing: 8) {
                    ForEach([15, 30, 60, 90], id: \.self) { minutes in
                        Button { timer.minutesInput = String(minutes) } label: {
                            Text(text("\(minutes) 分钟", "\(minutes) min"))
                                .font(.system(size: 11, weight: .regular)).fixedSize()
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .foregroundStyle(timer.configuredMinutes == minutes ? Color.primary : .secondary)
                                .background(Color.primary.opacity(timer.configuredMinutes == minutes ? 0.09 : 0.04), in: Capsule())
                        }.buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
                if timer.configuredMinutes == nil {
                    HStack(spacing: 6) {
                        Circle().fill(.red).frame(width: 5, height: 5).accessibilityHidden(true)
                        Text(text("请输入 1–720 的整数分钟数。", "Enter a whole number from 1 to 720 minutes."))
                    }.font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Divider()
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(timer.isRunning ? text("剩余时间", "Time remaining") : text("倒计时", "Countdown"))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        if timer.isRunning {
                            Text(timer.remainingText)
                                .font(.system(size: 24, weight: .medium, design: .rounded).monospacedDigit())
                        } else {
                            Text(timer.isFadingOut ? text("正在渐弱停止…", "Fading out…")
                                 : timer.hasExpired ? text("已结束", "Finished") : text("尚未开始", "Ready to start"))
                                .font(.system(size: 15, weight: .regular))
                        }
                    }
                    Spacer(minLength: 8)
                    if timer.isRunning {
                        Button(text("取消", "Cancel")) { timer.cancel() }
                            .buttonStyle(.bordered).controlSize(.regular).fixedSize()
                            .accessibilityIdentifier("cancelSleepTimer")
                    }
                    Button(timer.isRunning ? text("重新计时", "Restart") : text("开始计时", "Start timer")) { timer.start() }
                        .buttonStyle(.borderedProminent).controlSize(.regular).fixedSize()
                        .disabled(timer.configuredMinutes == nil)
                        .accessibilityIdentifier("startSleepTimer")
                }
            }
            SettingsCard {
                HStack(spacing: 16) {
                    SettingsRowTitle(title: text("在菜单栏显示剩余时间", "Show remaining time in menu bar"),
                                     subtitle: text("仅在计时期间显示，不影响电台名称设置。", "Visible while counting. Station name settings are unchanged."))
                    Spacer(minLength: 8)
                    Toggle(text("在菜单栏显示剩余时间", "Show remaining time in menu bar"), isOn: $settings.showSleepTimerInMenuBar)
                        .labelsHidden().toggleStyle(.switch).controlSize(.small).fixedSize()
                        .accessibilityIdentifier("showSleepTimerInMenuBar")
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text(text("菜单栏预览", "Menu bar preview")).font(.system(size: 11)).foregroundStyle(.secondary)
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        let name = settings.menuBarDisplay == .iconAndStation ? text("电台名称", "Station name") : nil
                        if settings.showSleepTimerInMenuBar && timer.isRunning {
                            Image(nsImage: MenuBarTitle.image(antenna: MenuBarAntenna.frames[2], stationName: name,
                                                            countdown: timer.remainingText))
                                .renderingMode(.template).accessibilityHidden(true)
                        } else {
                            Image(nsImage: MenuBarAntenna.frames[2]).accessibilityHidden(true)
                            Text(MenuBarTitle.text(stationName: name, countdown: nil)).fixedSize()
                        }
                    }
                    .font(.system(size: 13)).padding(.horizontal, 12).frame(height: 36)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            SettingsHint(text: text("暂停或切台不影响计时；退出 App 后清除。开始和取消定时不改变播放状态。",
                                    "Pausing or switching stations keeps counting; quitting clears it. Starting or cancelling a timer does not change playback."))
        }
    }
}
