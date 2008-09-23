" C Call-Tree Explorer (CCTree) <CCTree.vim>
"
"
" Script Info and Documentation 
"=============================================================================
"    Copyright: Copyright (C) August 2008, Hari Rangarajan
"               Permission is hereby granted to use and distribute this code,
"               with or without modifications, provided that this copyright
"               notice is copied with it. Like anything else that's free,
"               cctree.vim is provided *as is* and comes with no
"               warranty of any kind, either expressed or implied. In no
"               event will the copyright holder be liable for any damamges
"               resulting from the use of this software.
"
" Name Of File: CCTree.vim
"  Description: C Call-Tree Explorer Vim Plugin
"   Maintainer: Hari Rangarajan <hari.rangarajan@gmail.com>
"          URL: http://vim.sourceforge.net/scripts/script.php?script_id=2368
"  Last Change: September 21, 2008
"      Version: 0.3
"
"=============================================================================
" 
"  Description:
"       Plugin generates call-trees for any function or macro in real-time inside
"  Vim.
"
"  Requirements: 1) Cscope
"                2) Vim 7.xx 
"
"                Tested on Unix and the following Win32 versions:
"                + Cscope, mlcscope (WIN32)
"                       http://www.geocities.com/shankara_c/cscope.html
"                       http://www.bell-labs.com/project/wwexptools/packages.html
"
"                
"
"  Installation: 
"               Copy this file to ~/.vim/plugins/
"               or to /vimfiles/plugins/  (on Win32 platforms) 
" 
"               It might also be possible to load it as a filetype plugin
"               ~/.vim/ftplugin/c/
"
"               Need to set :filetype plugin on 
"           
"
"  Usage:
"           Build cscope database, for example:
"           > cscope -b -i cscope.files
"               [Tip: add -c option to build uncompressed databases for faster
"               load speeds]
"
"           Load database with command ":CCTreeLoadDB"
"           (Please note that it might take a while depending on the 
"           database size)
"
"           A database name, i.e., my_cscope.out, can be specified with 
"           the command. If not provided, a prompt will ask for the 
"           filename; default is cscope.out.
"
"           To unload database, use command ":CCTreeUnLoadDB"
"
"           Default Mappings:
"             Get reverse call tree for symbol  <C-\><
"             Get forward call tree for symbol  <C-\>>
"             Increase depth of tree and update <C-\>=
"             Decrease depth of tree and update <C-\>-
"
"             Open symbol in other window       <CR>
"             Preview symbol in other window    <Ctrl-P>
"
"          Command List:
"             CCTreeLoadDB                <dbname>
"             CCTreeUnLoadDB             
"             CCTreeTraceForward          <symbolname>
"             CCTreeTraceReverse          <symbolname>     
"             CCTreeRecurseDepthPlus     
"             CCTreeRecurseDepthMinus    
"
"
"
"          Settings:
"               Customize behavior by changing the variable settings
"
"               Cscope database file, g:CCTreeCscopeDb = "cscope.out"
"               Maximum call levels,   g:CCTreeRecursiveDepth = 3
"               Maximum visible(unfolded) level, g:CCTreeMinVisibleDepth = 3
"               Orientation of window,  g:CCTreeOrientation = "leftabove"
"                (standard vim options for split: [right|left][above|below])
"             
"  Limitations:
"           The accuracy of the call-tree will only be as good as the cscope 
"           database generation.
"           NOTE: Different flavors of Cscope have some known
"                 limitations due to the lexical analysis engine. This results
"                 in incorrectly identified function blocks, etc.
"
"  History:
"           Version 0.3:
"               September 21, 2008
"                 1. Support compressed cscope databases
"                 2. Display window related bugs fixed
"                 3. More intuitive display and folding capabilities
"               
"           Version 0.2:
"               September 12, 2008
"               (Patches from Yegappan Lakshmanan, thanks!)
"                 1. Support for using the plugin in Vi-compatible mode.
"                 2. Filtering out unwanted lines before processing the db.
"                 3. Command-line completion for the commands.
"                 4. Using the cscope db from any directory.
"
"           Version 0.1:
"                August 31,2008
"                 1. Cross-referencing support for only functions and macros
"                    Functions inside macro definitions will be incorrectly
"                    attributed to the top level calling function
"
"
"=============================================================================

if !exists('loaded_cctree') && v:version >= 700
  " First time loading the cctree plugin
  let loaded_cctree = 0
else
   finish 
endif

" Line continuation used here
let s:cpo_save = &cpoptions
set cpoptions&vim

" Global variables 
" Modify in .vimrc to modify default behavior
if !exists('CCTreeCscopeDb')
    let CCTreeCscopeDb = "cscope.out"
endif
if !exists('CCTreeRecursiveDepth')
    let CCTreeRecursiveDepth = 3
endif
if !exists('CCTreeMinVisibleDepth')
    let CCTreeMinVisibleDepth = 3
endif
if !exists('CCTreeOrientation')
    let CCTreeOrientation = "leftabove"
endif

" Plugin related local variables
let s:pluginname = 'CCTree'
let s:windowtitle = 'CCTree-Preview'
let s:CCTreekeyword = ''

" Disable perl interface
" Version 0.2, perl is disabled by default (might change in the future!)
" ENABLE_PERL
let s:allow_perl = 0


" Other state variables
let s:currentkeyword = ''
let s:currentdirection = ''
let s:dbloaded = 0
let s:symtable = {}
let s:save_statusline = ''
let s:lastbufname = ''

" Turn on/off debugs
let s:tag_debug=0

" Use the Decho plugin for debugging
function! DBGecho(...)
    if s:tag_debug
        Decho(a:000)
    endif
endfunction

function! DBGredir(...)
    if s:tag_debug
        Decho(a:000)
    endif
endfunction


function! s:CCTreeGetIdentifier(line)
    return matchlist(a:line, '^\t\(.\)\(.*\)')
endfunction


function! s:CCTreeSymbolCreate(name)
    if has_key(s:symtable, a:name)
        return s:symtable[a:name]
    endif

    let s:symtable[a:name] = {}
    let retval = s:symtable[a:name]
    let retval['name']= a:name
    let retval['child'] = {}
    let retval['parent'] = {}

    return retval
endfunction

function! s:CCTreeSymbolCalled(funcentry, newfunc)
    let a:funcentry['child'][a:newfunc['name']] = 1
endfunction

function! s:CCTreeSymbolCallee(funcentry, newfunc)
    let a:funcentry['parent'][a:newfunc['name']] = 1
endfunction


function! s:CCTreeInitStatusLine()
    let s:symlastprogress = 0
    let s:symprogress = 0
    let s:cursym = 0
    let s:currentstatus = ''
    let s:statusextra = ''
    
    let s:save_statusline = &statusline
    setlocal statusline=%{CCTreeStatusLine()}
endfunction
        
function! s:CCTreeRestoreStatusLine()
    let &statusline = s:save_statusline
endfunction

function! s:CCTreeBusyStatusLineUpdate(msg)
    let s:currentstatus = a:msg
    redrawstatus
endfunction

function! s:CCTreeBusyStatusLineExtraInfo(msg)
    let s:statusextra = a:msg
    redrawstatus
endfunction

function! CCTreeStatusLine()
    return s:pluginname. " ". s:currentstatus. " -- ". s:statusextra
endfunction

function! s:CCTreeWarningMsg(msg)
    echohl WarningMsg
    echo a:msg
    echohl None
endfunction


function! s:CCTreeLoadDB(db_name)
    let curfunc =  {}
    let newfunc =  {}
    let s:symtable = {}
    let s:dbloaded = 0

    let cscope_db = a:db_name
    if cscope_db == ''
        let cscope_db = input('Cscope database: ', g:CCTreeCscopeDb, 'file')
        if cscope_db == ''
            return
        endif
    endif

    if !filereadable(cscope_db)
        call s:CCTreeWarningMsg('Cscope database ' . cscope_db . ' not found')
        return
    endif

    call s:CCTreeBusyStatusLineUpdate('Loading database')
    let symbols = readfile(cscope_db)
    if empty(symbols)
        call s:CCTreeWarningMsg("Failed to read cscope database")
        call s:CCTreeRestoreStatusLine()
        return
    endif

    let s:symprogress = 0
    let s:symcur = 0
    let symindex = 0
    let symlocalstart = 0
    let symlocalcount = 0

    " Grab previous status line
    call s:CCTreeInitStatusLine()
    
    call s:CCTreeBusyStatusLineUpdate('Reading database')
    " Check if database was built uncompressed
   if symbols[0] !~ "cscope.*\-c"
        let s:dbcompressed = 1
    else
        let s:dbcompressed = 0
    endif
    " Filter-out lines that doesn't have relevant information
    call filter(symbols, 'v:val =~ "^\t[`#$}]"')

    if s:dbcompressed == 1
        let compressdict = s:Digraph_DictTable_Init()
        call s:CCTreeBusyStatusLineUpdate('Uncompressing database')
        call map(symbols, 's:Digraph_Uncompress_Fast(v:val, compressdict)')
    endif

    let s:symcount = len(symbols)
    let s:symcount1percent = s:symcount/100

    call s:CCTreeBusyStatusLineUpdate('Analyzing database')
    for a in symbols
        let s:symcur += 1
        if s:symcount1percent < s:symcur
            let s:symcur = 0
            let s:symprogress += 1
            call s:CCTreeBusyStatusLineExtraInfo("Processing ". s:symprogress. 
                        \ "\%, total ". s:symcount. " items")
            redrawstatus
        endif

        if a[1] == "`"
             if !empty(curfunc)
                 let newfunc = s:CCTreeSymbolCreate(a[2:])
                 call s:CCTreeSymbolCalled(curfunc, newfunc)
                 call s:CCTreeSymbolCallee(newfunc, curfunc)
             endif
        elseif a[1] == "$"
            let curfunc = s:CCTreeSymbolCreate(a[2:])
        elseif a[1] == "#"
            call s:CCTreeSymbolCreate(a[2:])
        elseif a[1] == "}"
            let curfunc = {}
        endif
    endfor

    call s:CCTreeRestoreStatusLine()
    let s:dbloaded = 1
    echomsg "Done building database"
endfunction


function! s:CCTreeUnloadDB()
    unlet s:symtable
    let s:dbloaded = 0
    " Force cleanup
    call garbagecollect()
endfunction 


function! s:CCTreeGetCallsForSymbol(symname, depth, direction)
    if (a:depth > g:CCTreeRecursiveDepth) 
        return {}
    endif

    if !has_key(s:symtable, a:symname)
        return {}            
    endif

    let symentry = s:symtable[a:symname]

    let calltree_dict = {}
    let calltree_dict['entry'] = a:symname

    for entry in keys(symentry[a:direction])
        if !has_key(calltree_dict, 'childlinks')
            let calltree_dict['childlinks'] = []
        endif
        let tmpDict = 
                \s:CCTreeGetCallsForSymbol(entry, a:depth+1, a:direction)
        call add(calltree_dict['childlinks'], tmpDict)
    endfor
    return calltree_dict
endfunction

func! s:FindOpenBuffer(filename)
    let bnrList = tabpagebuflist(tabpagenr())

    for bufnrs in bnrList
        if (bufname(bufnrs) == a:filename)
            let newWinnr = bufwinnr(bufnrs)
            exec newWinnr.'wincmd w'
            return 1
        endif
    endfor
    " Could not find the buffer
    return 0
endfunction

function! s:CCTreePreviewWindowLeave()
    call s:FindOpenBuffer(s:lastbufname)
endfunction

function! CCTreePreviewStatusLine()
    let rtitle= s:windowtitle. ' -- '. s:currentkeyword. 
            \'[Depth: '. g:CCTreeRecursiveDepth.','
    
    if s:currentdirection == 'parent' 
        let rtitle .= "(Reverse)"
    else
        let rtitle .= "(Forward)"
    endif

    return rtitle.']'
endfunction

function! s:CCTreePreviewWindowEnter()
    let s:lastbufname = bufname("%")
    if s:FindOpenBuffer(s:windowtitle) == 0
        exec  g:CCTreeOrientation." split ". s:windowtitle
        setlocal buftype=nofile
        setlocal bufhidden=wipe
        setlocal noswapfile
        setlocal nonumber
        setlocal noruler
 "       syntax on
        setlocal statusline=%=%{CCTreePreviewStatusLine()}

        syntax match CCTreeMarkers /|\?.*[<>]/
        syntax match CCTreeSymbol  / \k\+/

        let cpo_save = &cpoptions
        set cpoptions&vim

        call s:CCTreeBufferKeyMappingsCreate() 
        nnoremap <buffer> <silent> <C-p>  :CCTreePreviewBufferUsingTag<CR>
        nnoremap <buffer> <silent> <CR>  :CCTreeLoadBufferUsingTag<CR>
        nnoremap <buffer> <silent> <2-LeftMouse> :CCTreeLoadBufferUsingTag<CR>

        let &cpoptions = cpo_save
    endif
    setlocal foldmethod=expr
    setlocal foldexpr=s:CCTreeFoldExpr(getline(v:lnum))
    setlocal foldtext=CCTreeFoldText()
    let &l:foldlevel=g:CCTreeMinVisibleDepth
endfunction   


function! s:CCTreeDisplayTreeForALevel(dict, str, level)
    if !has_key(a:dict, 'entry')
        return
    endif

    let passdashtxt = repeat(" ", a:level*2)."|".repeat("-", a:level)
    let dashtxt = repeat(" ", a:level*2)."+".repeat("-", a:level)
    if s:currentdirection == 'parent' 
        let directiontxt = "< "
    else
        let directiontxt = "> "
    endif

    call setline(".", a:str. dashtxt. directiontxt. a:dict['entry'])
    exec "normal o"
 "   let &foldlevel = a:level
    if has_key(a:dict, 'childlinks')
        for a in a:dict['childlinks']
            call s:CCTreeDisplayTreeForALevel(a, 
                \   substitute(a:str.passdashtxt, "-", " ", "g"), a:level+1)
        endfor
    endif
endfunction

function! s:CCTreeDisplayTreeInWindow(atree)
    let incctreewin = 1
    if (bufname('%') != s:windowtitle) 
        call s:CCTreePreviewWindowEnter()
        let incctreewin = 0
    endif
    setlocal modifiable
    1,$d
    call s:CCTreeDisplayTreeForALevel(a:atree, '',  0) 
    exec "normal gg"
    " Need to force this again
    let &l:foldlevel=g:CCTreeMinVisibleDepth
    setlocal nomodifiable
    if (incctreewin == 0)
        call s:CCTreePreviewWindowLeave()
    endif
endfunction

function! s:CCTreeFoldExpr(line)
    let len = strlen(matchstr(a:line,'+-\+'))
    if len == 0
        let len = 1
    endif
    return '>'.len
endfunction


function! s:GetFoldOffset(exp, base)
    let retval = 1  
    let cnt = a:exp
    while cnt > 0
        let retval += cnt * a:base
        let cnt = cnt - 1
    endwhile
    return retval
endfunction

function! CCTreeFoldText()
    return getline(v:foldstart).
                \ " (+". (v:foldend - v:foldstart). 
                \  ')'. repeat(" ", winwidth(0))
endfunction


function! s:CCTreeStoreState(symbol, direction)
    let s:currentkeyword = a:symbol
    let s:currentdirection = a:direction
endfunction

function! s:CCTreeDBIsLoaded()
    if s:dbloaded == 0
        call s:CCTreeWarningMsg('CCTree database not loaded')
        return 0
    endif
    return 1
endfunction

" Trick to get the current script ID
map <SID>xx <SID>xx
let s:sid = substitute(maparg('<SID>xx'), '<SNR>\(\d\+_\)xx$', '\1', '')
unmap <SID>xx

function! s:CCTreeTraceTreeForSymbol(sym_arg, direction)
    if s:CCTreeDBIsLoaded() == 0
        return
    endif

    let symbol = a:sym_arg
    if symbol == ''
        let symbol = input('Trace symbol: ', expand('<cword>'),
                    \ 'customlist,<SNR>' . s:sid . 'CCTreeCompleteKwd')
        if symbol == ''
            return
        endif
    endif

    let atree = s:CCTreeGetCallsForSymbol(symbol, 0, a:direction)
    call s:CCTreeStoreState(symbol, a:direction)
    call s:CCTreeUpdateForCurrentSymbol()
endfunction

function! s:CCTreeUpdateForCurrentSymbol()
    if s:currentkeyword != ''
        let atree = s:CCTreeGetCallsForSymbol(s:currentkeyword, 0, s:currentdirection)
        call s:CCTreeDisplayTreeInWindow(atree)
    endif
endfunction


function! s:CCTreeGetCurrentKeyword()
    let s:CCTreekeyword = matchstr(expand("<cword>"), '\k\+')
endfunction

function! s:CCTreeLoadBufferFromKeyword()
    call s:CCTreeGetCurrentKeyword()
    if s:CCTreekeyword == ''
        return
    endif

    let g:dbg = s:CCTreekeyword
    try 
        exec 'wincmd p'
    catch
        call s:CCTreeWarningMsg('No buffer to load file')
    finally
        if (cscope_connection() > 0)
            exec "cstag ".s:CCTreekeyword
        else
            try
                exec "tag ".s:CCTreekeyword
            catch /^Vim\%((\a\+)\)\=:E426/
                call s:CCTreeWarningMsg('Tag '. s:CCTreekeyword .' not found')
                wincmd p
            endtry
        endif
    endtry
endfunction
    
function! s:CCTreePreviewBufferFromKeyword()
    call s:CCTreeGetCurrentKeyword()
    if s:CCTreekeyword == ''
        return
    endif
    exec "ptag ".s:CCTreekeyword
endfunction

function! s:CCTreeRecursiveDepthIncrease()
    let g:CCTreeRecursiveDepth += 1
    call s:CCTreeUpdateForCurrentSymbol()
endfunction

function! s:CCTreeRecursiveDepthDecrease()
    let g:CCTreeRecursiveDepth -= 1
    call s:CCTreeUpdateForCurrentSymbol()
endfunction


function! s:CCTreeCursorHoldHandle()
    call s:CCTreeGetCurrentKeyword()

    if s:CCTreekeyword == ''
        match none
    else 
       exec "match CCTreeKeyword /\\<".s:CCTreekeyword."\\>/"
    endif
endfunction

" CCTreeCompleteKwd
" Command line completion function to return names from the db
function! s:CCTreeCompleteKwd(arglead, cmdline, cursorpos)
    if a:arglead == ''
        return keys(s:symtable)
    else
        return filter(keys(s:symtable), 'v:val =~? a:arglead')
    endif
endfunction

function! s:CCTreeShowDB()
   echo s:symtable
endfunction
command! CCTreeShowDB call s:CCTreeShowDB()

augroup CCTreeGeneral
    au!
    autocmd CursorHold CCTree-Preview call s:CCTreeCursorHoldHandle()
augroup END


highlight link CCTreeKeyword Tag
highlight link CCTreeMarkers LineNr
highlight link CCTreeSymbol  Function


" Define commands
command! -nargs=? -complete=file CCTreeLoadDB  call s:CCTreeLoadDB(<q-args>)
command! -nargs=0 CCTreeUnLoadDB               call s:CCTreeUnloadDB()
command! -nargs=? -complete=customlist,s:CCTreeCompleteKwd
        \ CCTreeTraceForward call s:CCTreeTraceTreeForSymbol(<q-args>, 'child')
command! -nargs=? -complete=customlist,s:CCTreeCompleteKwd CCTreeTraceReverse  
            \ call s:CCTreeTraceTreeForSymbol(<q-args>, 'parent')
command! -nargs=0 CCTreeLoadBufferUsingTag call s:CCTreeLoadBufferFromKeyword()
command! -nargs=0 CCTreePreviewBufferUsingTag call s:CCTreePreviewBufferFromKeyword()
command! -nargs=0 CCTreeRecurseDepthPlus call s:CCTreeRecursiveDepthIncrease()
command! -nargs=0 CCTreeRecurseDepthMinus call s:CCTreeRecursiveDepthDecrease()

function! s:CCTreeBufferKeyMappingsCreate()
     nnoremap <buffer> <silent> <C-\><
                 \ :CCTreeTraceReverse <C-R>=expand("<cword>")<CR><CR> 
     nnoremap <buffer> <silent> <C-\>>
                 \ :CCTreeTraceForward <C-R>=expand("<cword>")<CR><CR> 
     nnoremap <buffer> <silent> <C-\>= :CCTreeRecurseDepthPlus<CR> 
     nnoremap <buffer> <silent> <C-\>- :CCTreeRecurseDepthMinus<CR> 
endfunction

augroup CCTreeMaps
au!
" Header files get detected as cpp?
" This is a bug in Vim 7.2, a patch needs to be applied to the runtime c
" syntax files
" For now, use this hack to make *.h files work
autocmd FileType * if &ft == 'c'|| &ft == 'cpp' |call s:CCTreeBufferKeyMappingsCreate()| endif
augroup END



" Cscope Digraph character compression/decompression routines
" the logic of these routines are based off the Cscope source code

let s:dichar1 = " teisaprnl(of)=c"	
let s:dichar2 = " tnerpla"

function! s:Digraph_DictTable_Init ()
    let dicttable = []
    let index = 0

    for dc1 in range(strlen(s:dichar1))
        for dc2 in range(strlen(s:dichar2))
            call add(dicttable, s:dichar1[dc1].s:dichar2[dc2])
        endfor
    endfor

    return dicttable
endfunction

function! s:Digraph_Uncompress_Slow (value, dicttable)
    let retval = ""
    for idx in range(strlen(a:value))
        let charext = char2nr(a:value[idx])-128
        if charext >= 0 
            let retval .= a:dicttable[charext]
        else
            let retval .= a:value[idx]
        endif
    endfor
    return retval
endfunction

function! s:Digraph_Uncompress_Fast (value, dicttable)
    let dichar_list = split(a:value, '[^\d128-\d255]\{}')
    let retval = a:value
    for adichar in dichar_list
        let retval = substitute(retval, '\C'.adichar, a:dicttable[char2nr(adichar)-128], "g")
    endfor
    return retval
endfunction


function! s:Digraph_Compress(value, dicttable)
    let index = 0
    let retval = ""

    while index < strlen(a:value)
        let dc1 = stridx(s:dichar1, a:value[index])
        if dc1 != -1
            let dc2 = stridx(s:dichar2, a:value[index+1])
            if dc2 != -1 
                let retval .= nr2char(128 + (dc1*8) + dc2)  
                " skip 2 chars
                let index += 2
                continue
            endif
        endif
        let retval .= a:value[index]
        let index += 1
    endwhile
    return retval
endfunction


" restore 'cpo'
let &cpoptions = s:cpo_save
unlet s:cpo_save

