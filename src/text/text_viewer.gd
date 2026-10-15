#! namespace ResourceView class TextViewer
extends CodeEdit

const TextSyntaxHighlighter = preload("uid://bkcb5j8x3qydh") #! resolve SyntaxHighlighters.Components.TextSyntaxHighlighter

func set_path(path:String):
	if path.get_extension() == "gd":
		if not syntax_highlighter is GDScriptSyntaxHighlighter:
			syntax_highlighter = GDScriptSyntaxHighlighter.new()
	else:
		if not syntax_highlighter is TextSyntaxHighlighter:
			syntax_highlighter = TextSyntaxHighlighter.new()
			syntax_highlighter.palette.apply_editor_settings()
		syntax_highlighter.extension = path.get_extension()
	
	text = FileAccess.get_file_as_string(path)
