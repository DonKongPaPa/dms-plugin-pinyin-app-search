import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Widgets

FocusScope {
    id: root

    property var pluginService: null

    implicitHeight: column.implicitHeight
    height: implicitHeight

    readonly property string pluginId: "pinyinAppSearch"

    function load(key, fallback) {
        return pluginService ? pluginService.loadPluginData(pluginId, key, fallback) : fallback;
    }

    function save(key, value) {
        if (pluginService)
            pluginService.savePluginData(pluginId, key, value);
    }

    Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 16
        spacing: 18

        Text {
            text: "拼音应用搜索"
            font.pixelSize: 18
            font.weight: Font.Bold
            color: Theme.surfaceText
        }

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            font.pixelSize: 13
            color: Theme.surfaceVariantText
            text: "输入拼音或首字母即可命中中文名应用（jsq → 计算器）。索引在运行时从 DesktopEntries 生成，不修改任何 .desktop 文件，删除插件即完全还原。"
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.outlineButton
            opacity: 0.3
        }

        Column {
            width: parent.width
            spacing: 8

            Text {
                text: "最多结果数：" + maxResultsField.text
                font.pixelSize: 14
                color: Theme.surfaceText
            }

            DankTextField {
                id: maxResultsField
                width: 140
                height: 40
                text: String(load("maxResults", 8))
                placeholderText: "8"
                onEditingFinished: {
                    const v = parseInt(text, 10);
                    if (v >= 1 && v <= 20)
                        save("maxResults", v);
                }
            }
        }

        Column {
            width: parent.width
            spacing: 8

            Text {
                text: "最短查询长度：" + minQueryField.text
                font.pixelSize: 14
                color: Theme.surfaceText
            }

            DankTextField {
                id: minQueryField
                width: 140
                height: 40
                text: String(load("minQueryLength", 2))
                placeholderText: "2"
                onEditingFinished: {
                    const v = parseInt(text, 10);
                    if (v >= 1 && v <= 5)
                        save("minQueryLength", v);
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                font.pixelSize: 12
                color: Theme.surfaceVariantText
                text: "DMS 的插件结果只在查询长度 ≥2 时参与搜索，设成 1 也不会提前出现。"
            }
        }

        Row {
            spacing: 10

            Switch {
                id: genericSwitch
                checked: load("matchGenericName", false)
                onToggled: save("matchGenericName", checked)
            }

            Text {
                text: "同时匹配类型名（如「媒体播放器」）的拼音"
                font.pixelSize: 14
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Row {
            spacing: 10

            Switch {
                id: commentSwitch
                checked: load("matchComment", false)
                onToggled: save("matchComment", checked)
            }

            Text {
                text: "同时匹配描述的拼音"
                font.pixelSize: 14
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
