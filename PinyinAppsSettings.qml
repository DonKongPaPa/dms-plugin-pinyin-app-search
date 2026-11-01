import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

// 用 DMS 官方插件设置组件（PluginSettings / ToggleSetting / SliderSetting / ListSettingWithInput）。
// 值的加载与保存由框架处理：它会在 pluginService 注入后才调 loadValue()，
// 自己写 Component.onCompleted 读设置会读不到（pluginService 在 Loader.onLoaded 才赋值）。
PluginSettings {
    id: root

    pluginId: "pinyinAppSearch"

    function tr(term) {
        return I18n.trFor(pluginId, term);
    }

    StyledText {
        width: parent.width
        text: root.tr("Type pinyin, initials, or a mix of both. jsq, jisq and jisuanqi all find 计算器. The index is built at runtime, so no .desktop file is modified.")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    ToggleSetting {
        settingKey: "noTrigger"
        label: root.tr("Always active (no trigger)")
        description: root.tr("Results appear alongside regular apps. Turn it off to require the trigger below.")
        defaultValue: true
    }

    StringSetting {
        settingKey: "trigger"
        label: root.tr("Trigger")
        description: root.tr("Only used when always-active is off. Type this prefix to see this plugin's results.")
        placeholder: "!"
        defaultValue: "!"
    }

    SliderSetting {
        settingKey: "maxResults"
        label: root.tr("Max results")
        description: root.tr("How many matches this plugin contributes to the list.")
        minimum: 1
        maximum: 20
        defaultValue: 8
    }

    SliderSetting {
        settingKey: "minQueryLength"
        label: root.tr("Min query length")
        description: root.tr("DMS does not run launcher plugins for queries shorter than 2 characters, so 1 has no effect there.")
        minimum: 1
        maximum: 5
        defaultValue: 2
    }

    ToggleSetting {
        settingKey: "matchGenericName"
        label: root.tr("Also match the generic name")
        description: root.tr("Indexes the generic name too, e.g. 媒体播放器 for media players.")
        defaultValue: false
    }

    ToggleSetting {
        settingKey: "matchComment"
        label: root.tr("Also match the comment")
        description: root.tr("Indexes the desktop comment. Noisier, so it is off by default.")
        defaultValue: false
    }

    ListSettingWithInput {
        settingKey: "aliases"
        label: root.tr("Custom aliases")
        description: root.tr("Give an app your own shortcut. Left is the alias (letters and digits only), right is an app name or desktop id.")
        fields: [
            {
                id: "alias",
                label: root.tr("Alias"),
                placeholder: "jisq2",
                width: 160,
                required: true
            },
            {
                id: "target",
                label: root.tr("App"),
                placeholder: "计算器",
                width: 320,
                required: true
            }
        ]
        defaultValue: []
    }
}
