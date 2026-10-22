import QtQuick
import qs.Common
import qs.Widgets

FocusScope {
    id: root

    property var pluginService: null

    implicitHeight: column.implicitHeight
    height: implicitHeight

    readonly property string pluginId: "pinyinAppSearch"

    // ---- 本地副本：settings 变更后热更新，避免 checked 绑定被内部 toggle 打断 ----
    property bool noTrigger: true
    property string trigger: ""
    property int maxResults: 8
    property int minQueryLength: 2
    property bool matchGenericName: false
    property bool matchComment: false

    function load(key, fallback) {
        return pluginService ? pluginService.loadPluginData(pluginId, key, fallback) : fallback;
    }

    function save(key, value) {
        if (pluginService)
            pluginService.savePluginData(pluginId, key, value);
    }

    function reload() {
        noTrigger = load("noTrigger", true);
        trigger = load("trigger", "");
        maxResults = load("maxResults", 8);
        minQueryLength = load("minQueryLength", 2);
        matchGenericName = load("matchGenericName", false);
        matchComment = load("matchComment", false);
    }

    Component.onCompleted: reload()

    Connections {
        target: root.pluginService
        function onPluginDataChanged(id) {
            if (id === root.pluginId)
                root.reload();
        }
    }

    Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.spacingM
        spacing: Theme.spacingL

        StyledText {
            width: parent.width
            text: "Pinyin App Search"
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.Medium
            color: Theme.surfaceText
        }

        StyledText {
            width: parent.width
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            text: "Type pinyin or initials to find apps with Chinese names (jsq → 计算器). The index is built at runtime from DesktopEntries, so no .desktop file is modified and removing the plugin restores everything."
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.outlineButton
            opacity: 0.3
        }

        DankToggle {
            width: parent.width
            text: "Always active (no trigger)"
            description: root.noTrigger ? "Results appear alongside regular apps." : "Results only appear after typing the trigger below."
            checked: root.noTrigger
            onToggled: isChecked => {
                root.noTrigger = isChecked;
                save("noTrigger", isChecked);
            }
        }

        Column {
            width: parent.width
            spacing: Theme.spacingS
            visible: !root.noTrigger

            StyledText {
                width: parent.width
                text: "Trigger"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
            }

            DankTextField {
                id: triggerField
                width: Math.min(parent.width, 200)
                height: 40
                text: root.trigger
                placeholderText: "!"
                onTextEdited: {
                    root.trigger = text.trim();
                    save("trigger", root.trigger);
                }
            }
        }

        Row {
            spacing: Theme.spacingM

            Column {
                spacing: Theme.spacingS

                StyledText {
                    text: "Max results: " + root.maxResults
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                }

                DankTextField {
                    id: maxResultsField
                    width: 120
                    height: 40
                    text: String(root.maxResults)
                    onTextEdited: {
                        const v = parseInt(text, 10);
                        if (v >= 1 && v <= 20) {
                            root.maxResults = v;
                            save("maxResults", v);
                        }
                    }
                }
            }

            Column {
                spacing: Theme.spacingS

                StyledText {
                    text: "Min query length: " + root.minQueryLength
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                }

                DankTextField {
                    id: minQueryField
                    width: 120
                    height: 40
                    text: String(root.minQueryLength)
                    onTextEdited: {
                        const v = parseInt(text, 10);
                        if (v >= 1 && v <= 5) {
                            root.minQueryLength = v;
                            save("minQueryLength", v);
                        }
                    }
                }
            }
        }

        StyledText {
            width: parent.width
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            text: "DMS skips plugin results for queries shorter than 2 characters, and outside the All and Plugins tabs."
        }

        DankToggle {
            width: parent.width
            text: "Also match the generic name"
            description: "Indexes GenericName too, e.g. 媒体播放器 for media players."
            checked: root.matchGenericName
            onToggled: isChecked => {
                root.matchGenericName = isChecked;
                save("matchGenericName", isChecked);
            }
        }

        DankToggle {
            width: parent.width
            text: "Also match the comment"
            description: "Indexes the desktop comment. Noisier, so it is off by default."
            checked: root.matchComment
            onToggled: isChecked => {
                root.matchComment = isChecked;
                save("matchComment", isChecked);
            }
        }
    }
}
