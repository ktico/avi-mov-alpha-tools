on run argv
    try
        set resultDialog to display dialog (item 1 of argv) with title "アルファチャンネルの警告" buttons {"キャンセル", "変換を続ける"} default button "キャンセル" cancel button "キャンセル" with icon caution
        return "yes"
    on error number -128
        return "no"
    end try
end run
