on run argv
    try
        set extensionName to item 1 of argv
        set selectedFile to choose file with prompt (extensionName & "ファイルを選択してください") of type {extensionName}
        return POSIX path of selectedFile
    on error number -128
        return ""
    end try
end run
