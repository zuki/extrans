defmodule Extrans do
  use Exgettext
  @doc """
  create .pot file

  extra documents in mix.exs project `config` is splited to chunk by blank line, and
  creating the .pot file by chunk.

  expected using with exgettext.


  """
  def xgettext(config, app, opt, switches \\ []) do
    {opt, _args, _rest}  = OptionParser.parse(opt, switches: switches)
    c = Keyword.get(config, :docs)
    docs = c.()
    files = docs[:extras]
    #source_root = docs[:source_root]
    app = Keyword.get(docs, :app, app)
    source_docroot = opt[String.to_atom(app)]
    # NOTE: Because only elixir has extras
    if source_docroot do
      Enum.map(files, fn(file) ->
                        outpath = Exgettext.Util.pot_path(app, file)
                        IO.inspect [source_docroot: source_docroot, file: file]
                        file = Path.join(source_docroot, file)
                        File.read!(file)
                        |> make_pot(%{:file => file, :outpath => outpath})
               end)
    end
  end
  @doc """

  """
  def conv(file, app, outpath) do
    :ok = File.mkdir_p(outpath)
    outfile = Path.join(outpath, file)
    File.read!(file)
    |> md(%{:file => file, :app => app})
    |> (fn(x) -> File.write!(outfile, x) end).()
  end
  def escape(x) do
    x = Regex.replace(~r/\"/, x, "\\\"")
    x = Regex.replace(~r/\n/, x, "\\\\n")
    x = Regex.replace(~r/\\/, x, "\\\\")
    x
  end
  def msgput(s) when is_binary(s) do
    msgput([s], "")
  end
  def msgput(s, delim \\ "\n") when is_list(s) do
    {q, eol} = if length(s) > 1 do
                 {"\"\"\n", "\\\\n"}
               else
                 {"", ""}
               end
    content = Enum.reduce(s, "", fn(x, acc) ->
                                   x = Regex.replace(~r/$/, x, eol)
                                   x = escape(x)
                                   #x = Regex.replace(~r/\"/, x, "\\\"")
                                   #x = Regex.replace(~r/\n/, x, "\\\\n")
                                   #x = Regex.replace(~r/\\/, x, "\\\\")
                                   #  delim_escaped = Regex.replace(~r/(\n)/, delim, "\\n")
                                   delim_escaped = ""
                                   acc <>  "\"#{x}#{delim_escaped}\"#{delim}"
                          end)
    if (:ets.info(:msgs) == :undefined) do
      :ets.new(:msgs, [:named_table])
    end
    if ! :ets.member(:msgs, content) do
      :ets.insert(:msgs, {content, ""})
      entry = "msgid  " <> q
      File.write!("msg.pot", entry, [:append])
      File.write("msg.pot", content, [:append])
      if (delim == "") do
        File.write!("msg.pot", "\n", [:append])
      end
      File.write!("msg.pot", "msgstr  \"\"\n", [:append])
      File.write!("msg.pot", "\n", [:append])
    end
  end
  def line_comment(meta, line) do
    "#: #{meta.file}:#{line}\n"
  end
  def is_code(cont) do
    String.split(cont, "\n")
    |> Enum.all?(&(Regex.match?(~r/^    /, &1)))
  end
  def put_entry(fd, ets, comment, cont) do
    if not(:ets.member(ets, cont)) && not(is_code(cont)) do
      :ets.insert(ets, {cont, comment})
      IO.write(fd, comment)
      IO.write(fd, "msgid ")
      x = cond do
        Regex.match?(~r/\n/, cont) ->
          IO.write(fd, "\"\"\n")
          x = Regex.replace(~r/\\/, cont, "\\\\\\")
          x = Regex.replace(~r/\"/, x, "\\\"")
          Regex.replace(~r/\n/, x, "\\n\"\n\"")
        true ->
          escape(cont)
      end
      IO.write(fd, "\"#{x}\"")
      IO.write(fd, "\nmsgstr \"\"\n\n")
    end
    cont
  end
  def translate(content, meta) do
    md(content, meta)
  end
  def md(content, meta) do
    String.split(content, "\n\n")
    |> Enum.map(fn(x) ->
                  Exgettext.Runtime.gettext(meta[:app], x)
                end)
    |> Enum.join("\n\n")
  end
  def make_pot(content, meta) do
    outfile = meta.outpath
    outpath = outfile
    :ok = File.mkdir_p(Path.dirname(outpath))
    {:ok, fd} = File.open(outpath, [:write, :utf8])
    cont = String.split(content, "\n\n")
    {r, _a} = Enum.map_reduce(cont, 0,
                    fn(x, a) ->
                      {{a + 1, x},
                       a + Enum.count(String.split(x, "\n")) + 1}
                    end)
    ets = :ets.new(:msgs, [:named_table])
    Enum.map(r, fn({line, c}) ->
                  comment = line_comment(meta, line)
                  put_entry(fd, ets, comment, c)
                  {line, cont}
             end)
    :ets.delete(:msgs)
    File.close(fd)
  end
end
