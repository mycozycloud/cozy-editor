### ------------------------------------------------------------------------
# CLASS FOR THE COZY NOTE EDITOR
#
# usage : 
#
# newEditor = new CNEditor( iframeTarget,callBack )
#   iframeTarget = iframe where the editor will be nested
#   callBack     = launched when editor ready, the context 
#                  is set to the editorCtrl (callBack.call(this))
# properties & methods :
#   replaceContent    : (htmlContent) ->  # TODO: replace with markdown
#   _keyDownCallBack : (e) =>
#   _insertLineAfter  : (param) ->
#   _insertLineBefore : (param) ->
#   
#   editorIframe      : the iframe element where is nested the editor
#   editorBody$       : the jquery pointer on the body of the iframe
#   _lines            : {} an objet, each property refers a line
#   _highestId        : 
#   _firstLine        : points the first line : TODO : not taken into account 
###


# Require is use only in development mode. During production build, files are
# concatenated.
if require?
    if not md2cozy?
        md2cozy = require('./md2cozy').md2cozy
    if not selection?
        selection = require('./selection').selection
  
###*
 * line$        : 
 * lineID       : 
 * lineType     : 
 * lineDepthAbs : 
 * lineDepthRel : 
 * lineNext     : 
 * linePrev     : 
###
class Line
    ###*
     * If no arguments, returns an empty object (only methods), otherwise
     * constructs a full line. The dom element of the line is inserted according
     * to the previous or next line given in the arguments.
     * @param  {Array}  Array of parameters :
     *   [ 
            editor        , # 
            type          , # 
            depthAbs      , # 
            depthRelative , # 
            prevLine      , # The prev line, null if nextLine is given
            nextLine      , # The next line, null if prevLine is given
            fragment        # [optional] a fragment to insert in the line, no br at the end
          ]
    ###
    constructor : ( ) ->
        if arguments.length == 0
            return
        else
            [ 
              editor        , # 
              type          , # 
              depthAbs      , # 
              depthRelative , # 
              prevLine      , # The prev line, null if nextLine is given
              nextLine      , # The next line, null if prevLine is given
              fragment        # [optional] a fragment to insert in the line, no br at the end
            ] = arguments

        editor._highestId += 1
        lineID = 'CNID_' + editor._highestId
        newLineEl = document.createElement('div')
        newLineEl.id = lineID
        newLineEl.setAttribute('class', type + '-' + depthAbs)
        if fragment?
            newLineEl.appendChild(fragment)
            newLineEl.appendChild(document.createElement('br'))
        else
            node = document.createElement('span')
            node.appendChild(document.createTextNode(''))
            newLineEl.appendChild(node)
            newLineEl.appendChild(document.createElement('br'))
        @line$ = $(newLineEl)
        
        if prevLine?
            @.linePrev = prevLine
            linesDiv = prevLine.line$[0].parentNode
            if prevLine.lineNext?
                nextL = prevLine.lineNext
                linesDiv.insertBefore(newLineEl,nextL.line$[0])
                @.lineNext     = nextL
                nextL.linePrev = @
            else
                linesDiv.appendChild(newLineEl)
                @.lineNext = null
            prevLine.lineNext = @
            
        else if nextLine?
            linesDiv = nextLine.line$[0].parentNode
            @.lineNext = nextLine
            linesDiv.insertBefore(newLineEl,nextLine.line$[0])
            if nextLine.linePrev? 
                @.linePrev = nextLine.linePrev
                nextLine.linePrev.lineNext = @
            else
                @.linePrev = null
            nextLine.linePrev = @
            
        @.lineID       = lineID
        @.lineType     = type
        @.lineDepthAbs = depthAbs
        @.lineDepthRel = depthRelative
        editor._lines[lineID] = @
        

    setType : (type) ->
        @lineType = type
        @line$.prop('class',"#{type}-#{@lineDepthAbs}")

    setDepthAbs : (absDepth) ->
        @lineDepthAbs = absDepth
        @line$.prop('class',"#{@lineType}-#{absDepth}")

    setTypeDepth : (type, absDepth) ->
        @lineType = type
        @lineDepthAbs = absDepth
        @line$.prop('class',"#{type}-#{absDepth}")

Line.clone = (line) ->
    clone = new Line()
    clone.line$        = line.line$.clone()
    clone.lineID       = line.lineID
    clone.lineType     = line.lineType
    clone.lineDepthAbs = line.lineDepthAbs
    clone.lineDepthRel = line.lineDepthRel
    clone.linePrev     = line.linePrev
    clone.lineNext     = line.lineNext
    return clone

class exports.CNeditor

    ###
    #   Constructor : newEditor = new CNEditor( iframeTarget,callBack )
    #       iframeTarget = iframe where the editor will be nested
    #       callBack     = launched when editor ready, the context 
    #                      is set to the editorCtrl (callBack.call(this))
    ###
    constructor : (@editorTarget, callBack) ->
        @editorTarget$ = $(@editorTarget)
        @callBack = callBack
        if @editorTarget.nodeName == "IFRAME"
            @isInIframe = true
            @editorTarget$.on 'load', @loadEditor
            @editorTarget.src = ''
        else if @editorTarget.nodeName == "DIV"
            @isInIframe = false
            @loadEditor()
        # return a ref to the editor's controler
        return this


    loadEditor : () =>
        if @isInIframe
            # preparation of the iframe
            editor_html$ = @editorTarget$.contents().find("html")
            @editorBody$ = editor_html$.find("body")
            @editorBody$.parent().attr('id','__ed-iframe-html')
            @editorBody$.attr("id","__ed-iframe-body")

            @document = @editorBody$[0].ownerDocument
            editor_head$ = editor_html$.find("head")
            cssLink = '<link id="editorCSS" '
            cssLink += 'href="stylesheets/CNeditor.css" rel="stylesheet">'
            editor_head$.html(cssLink)
        else
            @editorBody$ = @editorTarget$

            @getEditorSelection = () ->
                return rangy.getSelection()
            
            @saveEditorSelection = () ->
                sel = rangy.getSelection()
                return rangy.serializeSelection sel, true, @linesDiv

        # Create div that will contains line
        @linesDiv = document.createElement 'div'
        @linesDiv.setAttribute('id','editor-lines')
        @linesDiv.setAttribute('class','editor-frame')
        @linesDiv.setAttribute('contenteditable','true')
        @editorBody$.append @linesDiv
    
        # init clipboard div
        @_initClipBoard()

        # set the properties of the editor
        @_lines       = {}            # contains every line
        @newPosition  = true          # true if cursor has moved 
        @_highestId   = 0             # last inserted line identifier
        @_deepest     = 1             # current maximum indentation
        @_firstLine   = null          # pointer to the first line
        @_history     =               # for history management
            index        : 0
            history      : [null]
            historySelect: [null]
            historyScroll: [null]
            historyPos   : [null]
        @_lastKey     = null      # last pressed key (avoid duplication)

        # initialize event listeners
        @editorBody$.prop '__editorCtl', this

        # listen keydown on capturing phase (before bubbling)
        @linesDiv.addEventListener('keydown', @_keyDownCallBack, true)

        # if chrome => listen to keyup to correct the insertion of the
        # first caracter of an empty line
        @isFirefox = `'MozBoxSizing' in document.documentElement.style`
        @isSafari = Object.prototype.toString.call(window.HTMLElement)
        @isSafari = @isSafari.indexOf('Constructor') > 0
        @isChrome = !@isSafari && 
                 (`'WebkitTransform' in document.documentElement.style`)
        @isChromeOrSafari = @isChrome or @isSafari
        if @isChromeOrSafari
           @linesDiv.addEventListener('keyup', @_keyUpCorrection, false)

        # Listen to mouse to detect when caret is moved
        @linesDiv.addEventListener('mouseup', () =>
            @newPosition = true
        , true)

        @editorBody$.on 'keyup', () =>
            @editorTarget$.trigger jQuery.Event("onKeyUp")

        @editorBody$.on 'click', (event) =>
            @_lastKey = null
            if @_isCaretOnLink()
                rg = @currentSel.theoricalRange
                segment = selection.getSegment(rg.startContainer,rg.startOffset)
                # $(segment).popover({title:'mon titre',content:'mon contenu',placement:'bottom',container: '#well-editor'})
                # $(segment).popover('show')
                @_showUrlPopover(segment)

        @_initUrlPopover()

        @editorBody$.on 'paste', (event) =>
            @paste event

        # callback
        @callBack.call(this)


    _showUrlPopover : (segment) ->
        edges = segment.getBoundingClientRect()
        @urlPopover.segment = segment
        @urlPopover.style.left = edges.left + 'px'
        @urlPopover.style.top = edges.top + 17 + 'px'
        @urlPopover.urlInput.value = segment.href
        @urlPopover.textInput.value = segment.textContent
        @urlPopover.style.display = 'block'
        @urlPopover.urlInput.focus()
        @urlPopover.urlInput.select()
        return true

    _hideUrlPopover : (segment) =>
        @urlPopover.style.display = 'none'

    _validateUrlPopover : () =>
        @urlPopover.segment.href = @urlPopover.urlInput.value
        @urlPopover.segment.textContent = @urlPopover.textInput.value
        @urlPopover.style.display = 'none'

    _initUrlPopover : () ->
        frag = document.createDocumentFragment()
        pop = document.createElement('div')
        pop.className = 'CNE_urlpop'
        frag.appendChild(pop)
        pop.innerHTML = 
            """
            <span class="CNE_urlpop_head">Link</span>
            <span>(Ctrl+K)</span>
            <div class="CNE_urlpop-content">
                <a>Accéder au lien (Ctrl+click)</a></br>
                <span>url</span><input type="text"></br>
                <span>Text</span><input type="text"></br>
                <button>ok</button>
                <button>Cancel</button>
            </div>
            """
        b = document.querySelector('body')
        # b.appendChild(frag)
        b.insertBefore(frag,b.firstChild)
        [btnOK,btnCancel] = pop.querySelectorAll('button')
        btnOK.addEventListener('click',@_validateUrlPopover)
        # btnOK = pop.querySelector('button')
        btnCancel.addEventListener('click',@_hideUrlPopover)
        [urlInput,textInput] = pop.querySelectorAll('input')
        pop.urlInput = urlInput
        pop.textInput = textInput
        pop.addEventListener 'keypress', (e) =>
            if e.keyCode == 13
                @_validateUrlPopover()
            else if e.keyCode == 27
                @_hideUrlPopover()
        pop.addEventListener('focusout',@_hideUrlPopover) #don't work ?
        @urlPopover = pop

        return true


    setFocus : () ->
        @linesDiv.focus()

    # methods to deal selection on an iframe
    # this method is modified during construction if the editor target is not
    # an iframe
    getEditorSelection : () ->
        return rangy.getIframeSelection @editorTarget


    # this method is modified during construction if the editor target is not
    # an iframe
    saveEditorSelection : () ->
        sel = rangy.getIframeSelection @editorTarget
        return rangy.serializeSelection sel, true, @linesDiv


    ###*
     * Test if a break point is in a segment being a link. If yes returns the
     * segment, false otherwise.
     * @return {Boolean} The segment if in a link, false otherwise
    ###
    _isCaretOnLink : () ->
        rg = @updateCurrentSel().theoricalRange
        if rg.collapsed
            segment = selection.getSegment(rg.startContainer,rg.startOffset)
            return (segment.nodeName == 'A')
        else
            segment1 = selection.getSegment(rg.startContainer,rg.startOffset)
            segment2 = selection.getSegment(rg.endContainer,rg.endOffset)
            return (segment1 == segment2) && segment1.nodeName == 'A'


    ### ------------------------------------------------------------------------
    # EXTENSION : _updateDeepest
    # 
    # Find the maximal deep (thus the deepest line) of the text
    # TODO: improve it so it only calculates the new depth from the modified
    #       lines (not all of them)
    # TODO: set a class system rather than multiple CSS files. Thus titles
    #       classes look like "Th-n depth3" for instance if max depth is 3
    # note: These todos arent our priority for now
    ###
    _updateDeepest : ->
        max = 1
        lines = @_lines
        for c of lines
            if @editorBody$.children("#" + "#{lines[c].lineID}").length > 0 and
               lines[c].lineType == "Th" and lines[c].lineDepthAbs > max
                max = @_lines[c].lineDepthAbs
                
        # Following code is way too ugly to be kept
        # It needs to be replaced with a way to change a variable in a styl or
        # css file... but I don't even know if it is possible.
        if max != @_deepest
            @_deepest = max
            if max < 4
                @replaceCSS("stylesheets/app-deep-#{max}.css")
            else
                @replaceCSS("stylesheets/app-deep-4.css")
        
    ###* ------------------------------------------------------------------------
     * Initialize the editor content from a html string
     * The html string should not been pretified because of the spaces and
     * charriage return. 
     * If unPretify = true then a regex tries to set up things
    ###
    replaceContent : (htmlString, unPretify) ->
        if unPretify
            htmlString = htmlString.replace(/>[\n ]*</g, "><")
        @linesDiv.innerHTML = htmlString
        @_readHtml()

    ### ------------------------------------------------------------------------
    # Clear editor content
    ###
    deleteContent : ->
        emptyLine = '<div id="CNID_1" class="Tu-1"><span></span><br></div>'
        @linesDiv.innerHTML = emptyLine
        @_readHtml()
    
    ### ------------------------------------------------------------------------
    # Returns a markdown string representing the editor content
    ###
    getEditorContent : () ->
        md2cozy.cozy2md $(@linesDiv)

    ### ------------------------------------------------------------------------
    # Sets the editor content from a markdown string
    ###
    setEditorContent : (mdContent) ->
        cozyContent = md2cozy.md2cozy mdContent
        @linesDiv.innerHTML = cozyContent
        @_readHtml()
                  
    ###
    # Change the path of the css applied to the editor iframe
    ###
    replaceCSS : (path) ->
        document = @document
        linkElm = document.querySelector('#editorCSS')
        linkElm.setAttribute('href' , path)
        document.head.appendChild(linkElm)

    ###*
     * Return [metaKeyCode,keyCode] corresponding to the key strike combinaison. 
     * the string structure = [meta key]-[key]
     *   * [metaKeyCode] : (Alt)*(Ctrl)*(Shift)*
     *   * [keyCode] : (return|end|...|A|S|V|Y|Z)|(other) 
     * ex : 
     *   * "AltShift" & "up" 
     *   * "AltCtrl" & "down" 
     *   * "Shift" & "A"
     *   * "Ctrl" & "S"
     *   * "" & "other"
     * @param  {[type]} e [description]
     * @return {[type]}   [description]
    ###
    getShortCut : (e) ->
        metaKeyCode = `(e.altKey ? "Alt" : "") + 
                              (e.ctrlKey ? "Ctrl" : "") + 
                              (e.shiftKey ? "Shift" : "")`
        switch e.keyCode
            when 13 then keyCode = 'return'
            when 35 then keyCode = 'end'
            when 36 then keyCode = 'home'
            when 33 then keyCode = 'pgUp'
            when 34 then keyCode = 'pgDwn'
            when 37 then keyCode = 'left'
            when 38 then keyCode = 'up'
            when 39 then keyCode = 'right'
            when 40 then keyCode = 'down'
            when 9  then keyCode = 'tab'
            when 8  then keyCode = 'backspace'
            when 32 then keyCode = 'space'
            when 27 then keyCode = 'esc'
            when 46 then keyCode = 'suppr'
            else
                switch e.which
                    when 32 then keyCode = 'space'
                    when 8  then keyCode = 'backspace'
                    when 65 then keyCode = 'A'
                    when 66 then keyCode = 'B'
                    when 85 then keyCode = 'U'
                    when 75 then keyCode = 'K'
                    when 76 then keyCode = 'L'
                    when 83 then keyCode = 'S'
                    when 86 then keyCode = 'V'
                    when 89 then keyCode = 'Y'
                    when 90 then keyCode = 'Z'
                    else keyCode = 'other'
        shortcut = metaKeyCode + '-' + keyCode
        
        # a,s,v,y,z alone are simple characters
        if metaKeyCode == '' && keyCode in ['A', 'B', 'U', 'K', 'L', 'S', 'V', 'Y', 'Z']
            keyCode = 'other'

        return [metaKeyCode,keyCode]


    ### ------------------------------------------------------------------------
    #   _keyDownCallBack
    # 
    # The listener of keyPress event on the editor's iframe... the king !
    ###
    # 
    # Params :
    # e : the event object. Interesting attributes : 
    #   .which : added by jquery : code of the caracter (not of the key)
    #   .altKey
    #   .ctrlKey
    #   .metaKey
    #   .shiftKey
    #   .keyCode
    ###
    # SHORTCUT
    #
    # Definition of a shortcut : 
    #   a combination alt,ctrl,shift,meta
    #   + one caracter(.which) 
    #   or 
    #     arrow (.keyCode=dghb:) or 
    #     return(keyCode:13) or 
    #     bckspace (which:8) or 
    #     tab(keyCode:9)
    #   ex : shortcut = 'CtrlShift-up', 'Ctrl-115' (ctrl+s), '-115' (s),
    #                   'Ctrl-'
    ###
    # Variables :
    #   metaKeyStrokesCode : ex : ="Alt" or "CtrlAlt" or "CtrlShift" ...
    #   keyStrokesCode     : ex : ="return" or "_102" (when the caracter 
    #                               N°102 f is stroke) or "space" ...
    #
    _keyDownCallBack : (e) =>
        # 1- Prepare the shortcut corresponding to pressed keys
        [metaKeyCode,keyCode] = @getShortCut(e)
        shortcut = metaKeyCode + '-' + keyCode
        # console.log '_keyDownCallBack', shortcut
        switch e.keyCode
            when 16 #Shift
                e.preventDefault()
                return
            when 17 #Ctrl
                e.preventDefault()
                return
            when 18 #Alt
                e.preventDefault()
                return

        if @_lastKey != shortcut and \
               shortcut in ['-tab', '-return', '-backspace', '-suppr',
                            'CtrlShift-down', 'CtrlShift-up',
                            'CtrlShift-left', 'CtrlShift-right',
                            'Ctrl-B', 'Ctrl-U', 'Ctrl-K',
                            'Ctrl-V', 'Shift-tab', '-space', '-other', 'Alt-A']
            @_addHistory()
           
        @_lastKey = shortcut

        @currentSel =
            sel              : null
            range            : null
            startLine        : null
            endLine          : null
            rangeIsStartLine : null
            rangeIsEndLine   : null
            startBP          : null
            endBP            : null

        # 2- manage the newPosition flag
        #    newPosition == true if the position of caret or selection has been
        #    modified with keyboard or mouse.
        #    If newPosition == true and a character is typed or a suppression
        #    key is pressed, then selection must be "normalized" so that its
        #    break points are in text nodes. Normalization is done by 
        #    updateCurrentSel or updateCurrentSelIsStartIsEnd that is chosen 
        #    before to run the action corresponding to the shorcut.

        # 2.2- Set a flag if the user moved the caret with keyboard
        if keyCode in ['left','up','right','down',
                              'pgUp','pgDwn','end', 'home',
                              'return', 'suppr', 'backspace']      \
           and shortcut not in ['CtrlShift-down', 'CtrlShift-up',
                            'CtrlShift-right', 'CtrlShift-left']
            @newPosition = true
        
        # 4- the current selection is cleared everytime keypress occurs.
        # @currentSel = null
                 
        # 5- launch the action corresponding to the pressed shortcut
        switch shortcut
            when '-return'
                @updateCurrentSelIsStartIsEnd()
                @_return()
                @newPosition = false
                e.preventDefault()
            when '-backspace'
                @updateCurrentSelIsStartIsEnd()
                @_backspace()
                @newPosition = false
                e.preventDefault()
            when '-tab'
                @tab()
                e.preventDefault()
            when 'Shift-tab'
                @shiftTab()
                e.preventDefault()
            when '-suppr'
                @updateCurrentSelIsStartIsEnd()
                @_suppr(e)
                @newPosition = false
            when 'CtrlShift-down'
                @_moveLinesDown()
                e.preventDefault()
            when 'CtrlShift-up'
                @_moveLinesUp()
                e.preventDefault()
            when 'Ctrl-A'
                selection.selectAll(this)
                e.preventDefault()
            when 'Alt-L'
                @markerList()
                e.preventDefault()
            # TOGGLE LINE TYPE (Alt + a)                  
            when 'Alt-A'
                @toggleType()
                e.preventDefault()
            when '-other', '-space'
                @updateCurrentSel() if @newPosition
                @newPosition = false
            # PASTE (Ctrl + v)                  
            when 'Ctrl-V'
                true
            when 'Ctrl-B'
                @applyMetaDataOnSelection('CNE_strong')
                e.preventDefault()
            when 'Ctrl-U'
                @applyMetaDataOnSelection('CNE_underline')
                e.preventDefault()
            when 'Ctrl-K'
                @applyMetaDataOnSelection('A','https://www.cozycloud.cc/')
                e.preventDefault()
            # SAVE (Ctrl + s)                  
            when 'Ctrl-S'
                $(@editorTarget).trigger jQuery.Event('saveRequest')
                e.preventDefault()
            # UNDO (Ctrl + z)
            when 'Ctrl-Z'
                @unDo()
                e.preventDefault()
            # REDO (Ctrl + y)
            when 'Ctrl-Y'
                @reDo()
                e.preventDefault()
    

    ###*
     * updates @currentSel =
            sel              : {Selection} of the editor's document
            range            : sel.getRangeAt(0)
            startLine        : the 1st line of the current selection
            endLine          : the last line of the current selection
            rangeIsStartLine : {boolean} true if the selection ends at 
                               the end of its line : NOT UPDATE HERE - see
                               updateCurrentSelIsStartIsEnd
            rangeIsEndLine   : {boolean} true if the selection starts at 
                               the start of its line : NOT UPDATE HERE - see
                               updateCurrentSelIsStartIsEnd
            theoricalRange   : theoricalRange : normalization of the selection 
                               should put each break points in a node text. It 
                               doesn't work in chrome due to a bug. We therefore
                               store here the "theorical range" that the
                               selection should match. It means that if you are
                               not in chrome this is equal to range.
       If the caret position has just changed (@newPosition == true) then we
       normalise the selection (put its break points in text nodes)
       We also normalize if in Chrome because in order to have a range wit
       break points in text nodes.
     * @return {object} @currentSel
    ###
    updateCurrentSel : () ->

        # get the current range and normalize it
        sel = @getEditorSelection()
        range = sel.getRangeAt(0)

        # normalize if carret has been moved or if we are in Chrome
        if @newPosition or @isChromeOrSafari
            [newStartBP, newEndBP] = selection.normalize(range)
            theoricalRange = document.createRange()
            theoricalRange.setStart(newStartBP.cont,newStartBP.offset)
            theoricalRange.setEnd(newEndBP.cont,newEndBP.offset)
        else
            theoricalRange = range

        # get the lines corresponding to the range :
        startLine = @_lines[selection.getLineDiv(range.startContainer).id]
        endLine   = @_lines[selection.getLineDiv(range.endContainer  ).id]
        
        # upadte
        @currentSel =
            sel              : sel
            range            : range
            startLine        : startLine
            endLine          : endLine
            rangeIsStartLine : null
            rangeIsEndLine   : null
            theoricalRange   : theoricalRange

        return @currentSel


    ###*
     * updates @currentSel and check if range is at the start of begin of the
     * corresponding line. 
     * @currentSel =
            sel              : {Selection} of the editor's document
            range            : sel.getRangeAt(0)
            startLine        : the 1st line of the current selection
            endLine          : the last line of the current selection
            rangeIsStartLine : {boolean} true if the selection ends at 
                               the end of its line.
            rangeIsEndLine   : {boolean} true if the selection starts at 
                               the start of its line.
            theoricalRange   : theoricalRange : normalization of the selection 
                               should put each break points in a node text. It 
                               doesn't work in chrome due to a bug. We therefore
                               store here the "theorical range" that the
                               selection should match. It means that if you are
                               not in chrome this is equal to range.
       If the caret position has just changed (@newPosition == true) then we
       normalise the selection (put its break points in text nodes)
       We also normalize if in Chrome because in order to have a range wit
       break points in text nodes.
     * @return {object} @currentSel
    ###
    updateCurrentSelIsStartIsEnd : () ->

        sel                = @getEditorSelection()
        range              = sel.getRangeAt(0)

        # normalize if carret has been moved or if we are in Chrome
        if @newPosition or @isChromeOrSafari
            [newStartBP, newEndBP] = selection.normalize(range)
            theoricalRange = document.createRange()
            theoricalRange.setStart(newStartBP.cont,newStartBP.offset)
            theoricalRange.setEnd(newEndBP.cont,newEndBP.offset)
        else
            theoricalRange = range

        startContainer     = range.startContainer
        endContainer       = range.endContainer
        initialStartOffset = range.startOffset
        initialEndOffset   = range.endOffset

        # find startLine and the rangeIsStartLine
        {div,isStart,isEnd} = selection.getLineDivIsStartIsEnd(
                                            startContainer, initialStartOffset)
        startLine        = @_lines[div.id]
        rangeIsStartLine = isStart
        firstLineIsEnd   = isEnd

        # find endLine and the rangeIsEndLine
        {div,isStart,isEnd,} = selection.getLineDivIsStartIsEnd(
                                            endContainer, initialEndOffset)
        endLine         = @_lines[div.id]
        rangeIsEndLine  = isEnd
        lastLineIsStart = isStart

        # result
        @currentSel =
            sel              : sel
            range            : range
            startLine        : startLine
            endLine          : endLine
            rangeIsStartLine : rangeIsStartLine
            rangeIsEndLine   : rangeIsEndLine
            firstLineIsEnd   : firstLineIsEnd
            lastLineIsStart  : lastLineIsStart
            theoricalRange   : theoricalRange

        return @currentSel



    ###*
     * This function is called only if in Chrome, because the insertion of a caracter
     * by the browser may be out of a span. 
     * This is du to a bug in Chrome : you can create a range with its start 
     * break point in an empty span. But if you add this range to the selection,
     * then this latter will not respect your range and its start break point 
     * will be outside the range. When a key is pressed to insert a caracter,
     * the browser inserts it at the start break point, ie outside the span...
     * this function detects after each keyup is there is a text node outside a
     * span and move its content and the carret.
     * @param  {Event} e The key event
    ###
    _keyUpCorrection : (e) =>
        
        # loop on all elements of the div of the line. If there are textnodes,
        # insert them in the previous span, if none, to the next, if none create
        # one. Then delete the textnode.
        
        curSel = @updateCurrentSel()
        line   = curSel.startLine.line$[0]
        nodes  = line.childNodes
        l = nodes.length
        i = 0
        while i < l
            node = nodes[i]
            if node.nodeName == '#text'
                t = node.textContent
                if node.previousSibling
                    if node.previousSibling.nodeName in ['SPAN','A']
                        node.previousSibling.textContent += t
                    else
                        throw new Error('A line should be constituted of 
                            only <span> and <a>')
                else if node.nextSibling
                    if node.nextSibling.nodeName in ['SPAN','A']
                        node.nextSibling.textContent = t + 
                            node.nextSibling.textContent
                        # TODO : position of carret should be at the end of 
                        # string "t"
                    else if node.nextSibling.nodeName in ['BR']
                        newSpan = document.createElement('span')
                        newSpan.textContent = t
                        line.replaceChild(newSpan,node)
                        l += 1
                        i += 1
                    else
                        throw new Error('A line should be constituted of 
                            only <span> and <a>')
                else
                    throw new Error('A line should be constituted of a final
                            <br/>')
                line.removeChild(node)
                l -= 1 
            else
                i += 1

        # the final <br/> may be deleted by chrome : if so : add it.
        if nodes[l-1].nodeName != 'BR'
            brNode = document.createElement('br')
            line.appendChild(brNode)

        return true


    ###*
     * applies a metadata such as STRONG, UNDERLINED, A/href etc... on the
     * selected text.
     * @param  {string} metaData  The css class of the meta data or 'A' if link
     * @param  {string} others... Other params if metadata requires 
     *                            some (href for instance)
    ###
    applyMetaDataOnSelection : (metaData, others...) ->
        currentSel = @updateCurrentSelIsStartIsEnd()
        range = currentSel.theoricalRange
        # nothing to do if range is collapsed
        if range.collapsed
            return 
        # 1- create a range for each selected line and put them in 
        # an array (linesRanges)
        line = @currentSel.startLine
        endLine = @currentSel.endLine
        # case when the selection on the first line starts at the end of line
        if currentSel.firstLineIsEnd
            line = line.lineNext
            range.setStartBefore(line.line$[0].firstChild)
            selection.normalize(range)
        # case when the selection on the last line ends at the start of line
        if currentSel.lastLineIsStart
            endLine = endLine.linePrev
            range.setEndBefore(endLine.line$[0].lastChild)
            selection.normalize(range)
        # re check if range is collapsed
        if range.collapsed
            return
        # if a single line selection
        if line == endLine
            linesRanges = [range]
        else
            # range for the 1st line
            rg = range.cloneRange()
            rg.setEndBefore(line.line$[0].lastChild)
            selection.normalize(rg)
            linesRanges = [rg]
            # ranges for the lines in the middle
            line = line.lineNext
            while line != endLine
                rg = document.createRange()
                rg.selectNodeContents(line.line$[0])
                selection.normalize(rg)
                linesRanges.push(rg)
                line = line.lineNext
            # range for the last line
            rgEnd = range.cloneRange()
            rgEnd.setStartBefore(endLine.line$[0].firstChild)
            selection.normalize(rgEnd)
            linesRanges.push(rgEnd)

        # 2- decide if we apply metaData or remove it
        # For this we go throught each line and each selected segment to check
        # if metaData is applied or not.
        isAlreadyMeta = true
        for range in linesRanges
            isAlreadyMeta = isAlreadyMeta \
                              && 
                            @_checkIfMetaIsEverywhere(range, metaData, others) 
        addMeta = !isAlreadyMeta

        # 3- Apply the correct action on each lines and getback the breakpoints
        # corresponding of the initial range
        bps = []
        for range in linesRanges
            bps.push( @_applyMetaData(range, addMeta, metaData, others) )
        
        # 4- Position selection
        rg = document.createRange()
        bp1 = bps[0][0]
        bp2 = bps[bps.length - 1][1]
        rg.setStart(bp1.cont, bp1.offset)
        rg.setEnd(  bp2.cont, bp2.offset)
        if @isFirefox
            sel = this.currentSel.sel
        else
            sel = document.getSelection()
        sel.removeAllRanges()
        sel.addRange(rg)

        return true


    ###*
     * Walk though the segments delimited by the range (which must be in a 
     * single line) to check if the meta si on all of them.
     * @param  {range} range a range contained within a line. The range must be
     *                 normalized, ie its breakpoints must be in text nodes.
     * @param  {string} meta  The name of the meta data to look for. It can be
     *                        a css class ('CNE_strong' for instance), or a
     *                        metadata type ('A' for instance)
     * @param  {string} href  Others parameters of the meta data type if 
     *                        required (href value for a 'A' meta)
     * @return {boolean}       true if the meta data is already on all the 
     *                         segments delimited by the range.
    ###
    _checkIfMetaIsEverywhere : (range, meta, others) ->
        if meta == 'A'
            return @_checkIfAhrefIsEverywhere(range, others[0])
        else
            return @_checkIfCSSIsEverywhere(range,meta,)



    _checkIfCSSIsEverywhere : (range, CssClass) ->
        # Loop  on segments to decide wich action is to be done on all
        #    segments. For instance if all segments are strong the action is
        #    to un-strongify. If one segment is not bold, then the action is 
        #    to strongify.        
        segment    = range.startContainer.parentNode
        endSegment = range.endContainer.parentNode
        stopNext   = (segment == endSegment)
        loop
            if !segment.classList.contains(CssClass)
                return false
            else
                if stopNext
                    return true
                segment  = segment.nextSibling
                stopNext = (segment == endSegment)



    _checkIfAhrefIsEverywhere : (range, href) ->
        # Loop  on segments to decide wich action is to be done on all
        #    segments. For instance if all segments are strong the action is
        #    to un-strongify. If one segment is not bold, then the action is 
        #    to strongify.        
        segment    = range.startContainer.parentNode
        endSegment = range.endContainer.parentNode
        stopNext   = (segment == endSegment)
        loop
            if segment.nodeName != 'A' or segment.href != href
                return false
            else
                if stopNext
                    return true
                segment  = segment.nextSibling
                stopNext = (segment == endSegment)


    ###*
     * Add or remove a meta data to the segments delimited by the range. The
     * range must be within a single line and normalized (its breakpoints must
     * be in text nodes)
     * @param  {range} range    [description]
     * @param  {boolean} addMeta  True if the action is to add the metaData, 
     *                            False if the action is to remove it.
     * @param  {string} metaData The name of the meta data to look for. It can
     *                           be a css class ('CNE_strong' for instance), 
     *                           or a metadata type ('A' for instance)
     * @return {array}          [bp1,bp2] : the breakpoints corresponding to the
     *                          initial range after the line transformation.
    ###
    _applyMetaData : (range, addMeta, metaData, others) ->

        # 1- var
        lineDiv =  selection.getLineDiv(range.startContainer,range.startOffset)
        startSegment = range.startContainer.parentNode
        endSegment = range.endContainer.parentNode
        bp1 =
            cont   : range.startContainer
            offset : range.startOffset
        bp2 =
            cont   : range.endContainer
            offset : range.endOffset
        breakPoints = [bp1,bp2]

        # 2- create start segment
        #    We split the segment in two of the same type and class if :
        #      - the start break point is not strictly inside a node  text
        #      - the start segment doesn't have the required property
        
        if range.startOffset == range.startContainer.length
            startSegment = startSegment.nextSibling
            # rem : nextSibling can not be </br> because the start break point 
            # can not be at the end of the line.
            if startSegment == null
                return

        else if 0 < bp1.offset < bp1.cont.length
            isAlreadyMeta = @_isAlreadyMeta(startSegment, metaData, others)
            if       isAlreadyMeta && !addMeta \
                 or !isAlreadyMeta && addMeta
                rg = range.cloneRange()
                # case when bp1 and bp2 are in the same segment
                if endSegment == startSegment
                    # split segment1 in 2 fragments (frag1 & 2)
                    frag1 = rg.extractContents()
                    span = document.createElement(startSegment.nodeName)
                    if startSegment.className != ''
                        span.className = startSegment.className
                    span = frag1.appendChild(span)
                    span.appendChild(frag1.firstChild)
                    rg.setEndAfter(startSegment)
                    frag2 = rg.extractContents()
                    # insert fragments only in not empty (the notion of "empty"
                    # will probably evolve, for instance with images...)
                    rg.insertNode(frag2) if frag2.textContent != ''
                    rg.insertNode(frag1)
                    # update startSegment, endSegment, bp1 & bp2
                    startSegment = span
                    endSegment = startSegment
                    bp1.cont   = startSegment.firstChild
                    bp1.offset = 0
                    bp2.cont   = endSegment.lastChild
                    bp2.offset = endSegment.lastChild.length
                # case when bp1 and bp2 are in different segments
                else
                    rg.setEndAfter(startSegment)
                    frag1 = rg.extractContents()
                    startSegment = frag1.firstChild
                    bp1.cont   = startSegment.firstChild
                    bp1.offset = 0
                    rg.insertNode(frag1)

        # 3- create end segment
        #    We split the segment in two of the same type and class if :
        #      - the end break point is not strictly inside a node  text
        #      - the end segment doesn't have the required property
        
        if range.endOffset == 0
            endSegment = endSegment.previousSibling
            # rem : previousSibling should not be null because we check that the
            # range is not collapsed
            if endSegment == null
                return

        else if 0 < bp2.offset < bp2.cont.length
            # isAlreadyMeta = endSegment.classList.contains(metaData)
            isAlreadyMeta = @_isAlreadyMeta(endSegment, metaData, others)
            if  isAlreadyMeta && !addMeta or \
               !isAlreadyMeta && addMeta
                rg = range.cloneRange()
                rg.setStartBefore(endSegment)
                frag1 = rg.extractContents()
                if endSegment == startSegment
                    startSegment = frag1.firstChild
                    bp1.cont   = startSegment.firstChild
                    bp1.offset = 0
                endSegment = frag1.firstChild
                bp2.cont   = endSegment.lastChild
                bp2.offset = endSegment.lastChild.length
                rg.insertNode(frag1)
        
        # 4- apply the required style
        if metaData == 'A'
            bps = [bp1,bp2]
            @_applyAhrefToSegments(startSegment, endSegment, bps, addMeta, metaData, others[0])
        else
            @_applyCssToSegments(startSegment, endSegment, addMeta, metaData)

        # 5- collapse segments with same class
        @_fusionSimilarSegments(lineDiv, breakPoints)

        return [bp1,bp2]


    _isAlreadyMeta : (segment, metaData, others) ->
        if metaData == 'A'
            return segment.nodeName == 'A' && segment.href == others[0]
        else
            return segment.classList.contains(metaData)


    _applyAhrefToSegments : (startSegment, endSegment, bps, addMeta, metaData, href) ->
        segment  =  startSegment
        stopNext = (segment == endSegment)
        loop
            if addMeta
                if segment.nodeName == 'A'
                    segment.href = href
                else
                    a = document.createElement('A')
                    a.href = href
                    a.textContent = segment.textContent
                    a.classeName = segment.classeName
                    for bp in bps
                        if bp.cont.parentNode == segment
                            bp.cont = a.firstChild
                    segment.parentNode.replaceChild(a,segment)
                    segment = a
            else
                    span = document.createElement('SPAN')
                    span.textContent = segment.textContent
                    span.classeName = segment.classeName
                    for bp in bps
                        if bp.cont.parentNode == segment
                            bp.cont = span.firstChild
                    segment.parentNode.replaceChild(span,segment)
                    segment = span
                
            if stopNext
                break
            segment = segment.nextSibling
            stopNext = (segment == endSegment)
        return null



    _applyCssToSegments : (startSegment, endSegment, addMeta, cssClass) ->
        segment  =  startSegment
        stopNext = (segment == endSegment)
        loop
            if addMeta
                segment.classList.add(cssClass)
            else
                segment.classList.remove(cssClass)
            if stopNext
                break
            segment = segment.nextSibling
            stopNext = (segment == endSegment)
        return null


    _fusionSimilarSegments : (lineDiv, breakPoints) -> 
        prevSegment = lineDiv.firstChild
        segment     = prevSegment.nextSibling
        while segment.nodeName != 'BR'
            isSimilar = @_compareSegments(prevSegment, segment)
            if isSimilar
                @_fusionSegments(prevSegment, segment, breakPoints)
                segment     = prevSegment.nextSibling
            else
                prevSegment = segment
                segment     = segment.nextSibling

        return breakPoints


    _compareSegments : (segment1, segment2) ->
        if segment1.nodeName != segment2.nodeName
            return false
        else if segment1.nodeName == 'A'
            if segment1.href != segment2.href
                return false

        list1 = segment1.classList
        list2 = segment2.classList
        
        if list1.length != list2.length
            return false

        if list1.length == 0
            return true

        for clas in list2
            if !list1.contains(clas)
                return false
        return true


    _fusionSegments : (segment1, segment2, breakPoints) ->
        children = Array.prototype.slice.call(segment2.childNodes)
        for child in segment2.childNodes
            segment1.appendChild(child)

        txtNode1 = segment1.firstChild
        txtNode2 = txtNode1.nextSibling
        while txtNode2 != null
            if txtNode1.nodeName == '#text' == txtNode2.nodeName 
                for bp in breakPoints
                    if bp.cont == txtNode2
                        bp.cont = txtNode1
                        bp.offset = txtNode1.length + bp.offset
                txtNode1.textContent += txtNode2.textContent
                segment1.removeChild(txtNode2)
                txtNode2 = txtNode1.nextSibling
            else
                txtNode1 = segment1.firstChild
                txtNode2 = txtNode1.nextSibling

        segment2.parentNode.removeChild(segment2)
        return breakPoints



    ### ------------------------------------------------------------------------
    #  _suppr :
    # 
    # Manage deletions when suppr key is pressed
    ###
    _suppr : (event) ->

        startLine = @currentSel.startLine
        # 1- Case of a caret "alone" (no selection)
        if @currentSel.range.collapsed

            # 1.1 caret is at the end of the line
            if @currentSel.rangeIsEndLine

                # if there is a next line : modify the selection to make
                # a multiline deletion
                if startLine.lineNext != null
                    @currentSel.range.setEndBefore(startLine.lineNext.line$[0].firstChild)
                    @currentSel.theoricalRange = @currentSel.range
                    @currentSel.endLine = startLine.lineNext
                    @_deleteMultiLinesSelections()
                    
                # if there is no next line :
                # no modification, just prevent default action
                else
                    # console.log '_suppr 2 - test '

            # 1.2 caret is in the middle of the line : delete one caracter
            else
                # console.log '_suppr 3 - test '
                # we consider that we are in a text node
                textNode = @currentSel.range.startContainer
                startOffset = @currentSel.range.startOffset
                txt = textNode.textContent
                textNode.textContent = txt.substr(0,startOffset) + txt.substr(startOffset+1)
                range = rangy.createRange()
                range.collapseToPoint textNode, startOffset
                @currentSel.sel.setSingleRange range

        # 2- Case of a selection contained in a line
        else if @currentSel.endLine == startLine
            # sel can be safely deleted thanks to normalization that have set
            # the selection correctly within the line.
            # console.log '_suppr 4 - test '
            @currentSel.range.deleteContents()

        # 3- Case of a multi lines selection
        else
            # console.log '_suppr 5 - test '
            @_deleteMultiLinesSelections()

        event.preventDefault()
        return false

    ### ------------------------------------------------------------------------
    #  _backspace
    # 
    # Manage deletions when backspace key is pressed
    ###
    _backspace : () ->

        sel = @currentSel
                    
        startLine = sel.startLine

        # 1- Case of a caret "alone" (no selection)
        if sel.range.collapsed
            # 1.1 caret is at the beginning of the line
            if sel.rangeIsStartLine
                # if there is a previous line : modify the selection to make
                # a multiline deletion
                if startLine.linePrev != null
                    # console.log '_backspace 3 - test ok'
                    cloneRg = sel.range.cloneRange()
                    cloneRg.setStartBefore(startLine.linePrev.line$[0].lastChild)
                    selection.normalize(cloneRg)
                    @currentSel.theoricalRange = cloneRg
                    sel.startLine = startLine.linePrev
                    @_deleteMultiLinesSelections()

                # if there is no previous line = backspace at the beginning of 
                # first line : no effect, nothing to do.
                # else
                #     console.log '_backspace 4 - test ok'

            # 1.2 caret is in the middle of the line : delete one caracter
            else
                # console.log '_backspace 5 - deletion of one caracter - test ok'
                # we consider that we are in a text node
                textNode = sel.range.startContainer
                startOffset = sel.range.startOffset
                txt = textNode.textContent
                textNode.textContent = txt.substr(0,startOffset-1) + txt.substr(startOffset)
                range = rangy.createRange()
                range.collapseToPoint textNode, startOffset-1
                @currentSel.sel.setSingleRange range
                @currentSel = null

        # 2- Case of a selection contained in a line
        else if sel.endLine == startLine
                # console.log '_backspace 6 - test ok'
            # sel can be safely deleted thanks to normalization that have set
            # the selection correctly within the line.
            sel.range.deleteContents()

        # 3- Case of a multi lines selection
        else
            @_deleteMultiLinesSelections()

        return true


    ### ------------------------------------------------------------------------
    #  titleList
    # 
    # Turn selected lines in a title List (Th)
    ###

    titleList : (l) ->
        # @_addHistory()
        # 1- find first and last div of the lines to turn into markers
        if l?
            startDivID = l.lineID
            endLineID  = startDivID
        else
            range = @getEditorSelection().getRangeAt(0)
            startDiv = selection.getLineDiv(
                    range.startContainer, 
                    range.startOffset
                )
            endDiv = selection.getLineDiv(
                    range.endContainer, 
                    range.endOffset
                )
            startDivID =  startDiv.id
            endLineID = endDiv.id
            
        # 2- loop on each line between the first and last line selected
        # TODO : deal the case of a multi range (multi selections).
        line = @_lines[startDivID]
        loop
            switch line.lineType
                when 'Tu','To'
                    @_toggleLineType(line)
                when 'Lh'
                    line.setType('Th')
                when 'Lu'
                    line.setType('Tu')
                    @_toggleLineType(line)

            if line.lineID == endLineID
                break
            line = line.lineNext



    ### ------------------------------------------------------------------------
    #  markerList
    # 
    #  Turn selected lines in a Marker List
    ###

    markerList : (l) ->
        @_addHistory()
        # 1- find first and last div of the lines to turn into markers
        if l?
            startDivID = l.lineID
            endLineID  = startDivID
        else
            range = @getEditorSelection().getRangeAt(0)
            startDiv = selection.getLineDiv(
                    range.startContainer, 
                    range.startOffset
                )
            endDiv = selection.getLineDiv(
                    range.endContainer, 
                    range.endOffset
                )
            startDivID =  startDiv.id
            endLineID = endDiv.id
            
        # 2- loop on each line between the first and last line selected
        # TODO : deal the case of a multi range (multi selections).
        line = @_lines[startDivID]
        loop
            switch line.lineType
                when 'Th','To'
                    @_toggleLineType(line)
                when 'Lh', 'Lo'
                    line.setTypeDepth('Tu',line.lineDepthAbs+1)
                when 'Lu'
                    line.setType('Tu')

            if line.lineID == endLineID
                break
            line = line.lineNext


    ### ------------------------------------------------------------------------
    #  _findDepthRel
    # 
    # Calculates the relative depth of the line
    #   usage   : cycle : Tu => To => Lx => Th
    #   param   : line : the line we want to find the relative depth
    #   returns : a number
    # 
    ###
    _findDepthRel : (line) ->
        if line.lineDepthAbs == 1
            if line.lineType[1] == "h"
                return 0
            else
                return 1
        else
            linePrev = line.linePrev
            while linePrev!=null and linePrev.lineDepthAbs >= line.lineDepthAbs
                linePrev = linePrev.linePrev
            if linePrev != null
                return linePrev.lineDepthRel+1
            else
                return 0


    ### ------------------------------------------------------------------------
    # Toggle the selected lines type
    #   cycle : Tu <=> Th
    ###
    toggleType : () ->
        # 1- Variables
        sel   = @getEditorSelection()
        range = sel.getRangeAt(0)
        
        startDiv = selection.getLineDiv range.startContainer, range.startOffset
        endDiv = selection.getLineDiv range.endContainer, range.endOffset
                
        # 2- find first and last div corresponding to the 1rst and
        #    last selected lines
        endLineID = endDiv.id

        # 3- loop on each line between the first and last line selected
        # TODO : deal the case of a multi range (multi selections). 
        #        Currently only the first range is taken into account.
        line = @_lines[startDiv.id]
        depthIsTreated = {}
        currentDepth = line.lineDepthAbs
        depthIsTreated[currentDepth] = false
        loop
            if ! depthIsTreated[currentDepth]
                done = @_toggleLineType(line)
                depthIsTreated[line.lineDepthAbs] = done
            if line.lineID == endDiv.id
                return
            line = line.lineNext
            if line.lineDepthAbs < currentDepth
                depthIsTreated[currentDepth] = false
                currentDepth = line.lineDepthAbs
            else
                currentDepth = line.lineDepthAbs
                

    _toggleLineType : (line) ->
        switch line.lineType
            
            when 'Tu'
                lineTypeTarget = 'Th'
                # transform all its next siblings and lines in Th or Lh
                l = line.lineNext
                while l!=null and l.lineDepthAbs >= line.lineDepthAbs
                    if l.lineDepthAbs == line.lineDepthAbs
                        if l.lineType == 'Tu'
                            l.setType('Th')
                        else if l.lineType == 'Lu'
                            l.setType('Lh')
                        else # when on the same level there are both u and h
                            break # manage only contiguous lines and siblings
                    l = l.lineNext
                # transform all its previous siblings and lines in Th or Lh
                l = line.linePrev
                while l!=null and l.lineDepthAbs >= line.lineDepthAbs
                    if l.lineDepthAbs == line.lineDepthAbs
                        if l.lineType == 'Tu'
                            l.setType('Th')
                        else if l.lineType == 'Lu'
                            l.setType('Lh')
                        else
                            break
                    l = l.linePrev

            when 'Th'
                lineTypeTarget = 'Tu'
                # transform all its next siblings and lines in Tu or Lu
                l = line.lineNext
                while l!=null and l.lineDepthAbs >= line.lineDepthAbs
                    if l.lineDepthAbs == line.lineDepthAbs
                        if l.lineType == 'Th'
                            l.setType('Tu')
                        else if l.lineType == 'Lh'
                            l.setType('Lu')
                        else
                            break
                    l = l.lineNext
                l = line.linePrev
                # transform all its previous siblings and lines in Tu or Lu
                while l!=null and l.lineDepthAbs >= line.lineDepthAbs
                    if l.lineDepthAbs == line.lineDepthAbs
                        if l.lineType == 'Th'
                            l.setType('Tu')
                        else if l.lineType == 'Lh'
                            l.setType('Lu')
                        else
                            break
                    l = l.linePrev

            # when 'Lu'
            #     @markerList(line)

            # when 'Lh'
            #     @titleList( line)

            when 'Lu'
                lineTypeTarget = 'Tu'

            when 'Lh'
                lineTypeTarget = 'Th'

            else
                return false

        line.setType(lineTypeTarget)
        return true



    ### ------------------------------------------------------------------------
    #  tab
    # 
    # tab keypress
    #   l = optional : a line to indent. If none, the selection will be indented
    ###
    tab :  (l) ->
        # 1- Variables
        if l?
            startDiv = l.line$[0]
            endDiv   = startDiv
        else
            sel   = @getEditorSelection()
            range = sel.getRangeAt(0)

            startDiv = selection.getLineDiv(
                    range.startContainer, 
                    range.startOffset
                )
            endDiv = selection.getLineDiv(
                    range.endContainer, 
                    range.endOffset
                )
        
        endLineID = endDiv.id

        # 2- loop on each line between the first and last line selected
        # TODO : deal the case of a multi range (multi selections). 
        #        Currently only the first range is taken into account.
        line = @_lines[startDiv.id]
        loop
            @_tabLine(line)
            if line.lineID == endLineID
                break
            else
                line = line.lineNext


    _tabLine : (line) ->
        switch line.lineType
            when 'Tu','Th','To'
                # find previous sibling to check if a tab is possible 
                # (no tab if no previous sibling)
                prevSibling = @_findPrevSibling(line)
                if prevSibling == null
                    return
                # determine new lineType
                if prevSibling.lineType == 'Th'
                    typeTarget = 'Lh'
                else if prevSibling.lineType == 'Tu'
                    typeTarget = 'Lu'
                else
                    typeTarget = 'Lo'

            when 'Lh', 'Lu', 'Lo'
                depthAbsTarget = line.lineDepthAbs + 1

                # find next sibling
                nextSib = @_findNextSibling(line, depthAbsTarget)
                nextSibType = if nextSib == null then null else nextSib.lineType

                # find previous sibling
                prevSib = @_findPrevSibling(line, depthAbsTarget)
                prevSibType = if prevSib == null then null else prevSib.lineType

                typeTarget = @_chooseTypeTarget(prevSibType,nextSibType)
                
                if typeTarget == 'Th'
                    line.lineDepthAbs += 1
                    line.lineDepthRel  = 0
                else
                    line.lineDepthAbs += 1
                    line.lineDepthRel += 1

        line.setType(typeTarget)

    _chooseTypeTarget : (prevSibType,nextSibType) ->
        # If there are no siblings => Tu
        if  prevSibType == nextSibType == null
            typeTarget = 'Tu'
        # If There are 2 identical, => use their type
        else if prevSibType == nextSibType
            typeTarget = nextSibType
        # If only one sibling, use its type
        else if prevSibType == null
            typeTarget = nextSibType
        # If only one sibling, use its type
        else if nextSibType == null
            typeTarget = prevSibType
        # If the two siblings have differents types => Tu
        else
            typeTarget = 'Tu'
        return typeTarget


    ### ------------------------------------------------------------------------
    #  shiftTab
    #   param : myRange : if defined, refers to a specific region to untab
    ###
    shiftTab : (range) ->

        # 1- Variables
        unless range?
            sel   = @getEditorSelection()
            range = sel.getRangeAt(0)
            
        startDiv = selection.getLineDiv range.startContainer, range.startOffset
        endDiv = selection.getLineDiv range.endContainer, range.endOffset
        
        endLineID = endDiv.id
        
        # 2- loop on each line between the first and last line selected
        line = @_lines[startDiv.id]
        loop
            @_shiftTabLine(line)
            if line.lineID == endDiv.id
                break
            else
                line = line.lineNext
    ###*
     * un-tab a single line
     * @param  {line} line the line to un-tab
    ###
    _shiftTabLine : (line) ->
        switch line.lineType
            when 'Tu','Th','To'
                # find the closest parent to choose the new lineType.
                parent = line.linePrev
                while parent != null and parent.lineDepthAbs >= line.lineDepthAbs
                    parent = parent.linePrev
                if parent == null
                    return

                # if lineNext is a Lx of line, then it must be turned in a Tx
                if line.lineNext? and 
                  line.lineNext.lineType[0] == 'L' and
                  line.lineNext.lineDepthAbs == line.lineDepthAbs
                    nextL = line.lineNext
                    nextL.setType('T'+nextL.lineType[1])
                # if the line under is already deaper, all sons must have
                # their depth reduced
                if line.lineNext? and line.lineNext.lineDepthAbs > line.lineDepthAbs
                    nextL = line.lineNext
                    while nextL.lineDepthAbs > line.lineDepthAbs
                        nextL.setDepthAbs(nextL.lineDepthAbs - 1)
                        nextL = nextL.lineNext
                    if nextL? and nextL.lineType[0]=='L'
                        nextL.setType('T'+nextL.lineType[1])
                typeTarget = parent.lineType
                typeTarget = "L" + typeTarget.charAt(1)
                line.lineDepthAbs -= 1
                line.lineDepthRel -= parent.lineDepthRel

            when 'Lh', 'Lu', 'Lo'
                depthAbsTarget = line.lineDepthAbs

                # find next sibling
                nextSib = @_findNextSibling(line, depthAbsTarget)
                nextSibType = if nextSib == null then null else nextSib.lineType
                
                # find previous sibling
                prevSib = @_findPrevSibling(line, depthAbsTarget)
                prevSibType = if prevSib == null then null else prevSib.lineType

                typeTarget = @_chooseTypeTarget(prevSibType,nextSibType)

        line.setType(typeTarget)



    ### ------------------------------------------------------------------------
    #  _return
    # return keypress
    #   e = event
    ###
    _return : () ->
        currSel   = this.currentSel
        startLine = currSel.startLine
        endLine   = currSel.endLine

        # 1- Delete the selections so that the selection is collapsed
        if currSel.range.collapsed
            
        else if endLine == startLine
            currSel.range.deleteContents()
        else
            @_deleteMultiLinesSelections()
            currSel   = @updateCurrentSelIsStartIsEnd()
            startLine = currSel.startLine
       
        # 2- Caret is at the end of the line
        if currSel.rangeIsEndLine
            newLine = @_insertLineAfter (
                sourceLine         : startLine
                targetLineType     : startLine.lineType
                targetLineDepthAbs : startLine.lineDepthAbs
                targetLineDepthRel : startLine.lineDepthRel
            )
            # Position caret
            range4sel = rangy.createRange()
            range4sel.collapseToPoint(newLine.line$[0].firstChild.firstChild,0)
            currSel.sel.setSingleRange(range4sel)

        # 3- Caret is at the beginning of the line
        else if currSel.rangeIsStartLine
            newLine = @_insertLineBefore (
                sourceLine         : startLine
                targetLineType     : startLine.lineType
                targetLineDepthAbs : startLine.lineDepthAbs
                targetLineDepthRel : startLine.lineDepthRel
            )
            # Position caret
            range4sel = rangy.createRange()
            range4sel.collapseToPoint(startLine.line$[0].firstChild.firstChild,0)
            currSel.sel.setSingleRange(range4sel)

        # 4- Caret is in the middle of the line
        else
            # Deletion of the end of the original line
            currSel.range.setEndBefore( startLine.line$[0].lastChild )
            endOfLineFragment = currSel.range.extractContents()
            currSel.range.deleteContents()
            # insertion
            newLine = @_insertLineAfter (
                sourceLine         : startLine
                targetLineType     : startLine.lineType
                targetLineDepthAbs : startLine.lineDepthAbs
                targetLineDepthRel : startLine.lineDepthRel
                fragment           : endOfLineFragment
            )
            # Position caret
            range4sel = rangy.createRange()
            range4sel.collapseToPoint(newLine.line$[0].firstChild.firstChild,0)
            
            currSel.sel.setSingleRange(range4sel)
            this.currentSel = null



    ### ------------------------------------------------------------------------
    #  _findParent1stSibling
    # 
    # find the sibling line of the parent of line that is the first of the list
    # ex :
    #   . Sibling1 <= _findParent1stSibling(line)
    #   . Sibling2
    #   . Parent
    #      . child1
    #      . line     : the line in argument
    # returns null if no previous sibling, the line otherwise
    # the sibling is a title (Th, Tu or To), not a line (Lh nor Lu nor Lo)
    ###
    _findParent1stSibling : (line) ->
        lineDepthAbs = line.lineDepthAbs
        linePrev = line.linePrev
        if linePrev == null
            return line
        if lineDepthAbs <= 2
            # in the 2 first levels the answer is _firstLine
            while linePrev.linePrev != null
                linePrev = linePrev.linePrev
            return linePrev
        else
            while linePrev != null and linePrev.lineDepthAbs > (lineDepthAbs-2)
                linePrev = linePrev.linePrev
            return linePrev.lineNext

    ###* -----------------------------------------------------------------------
     * Find the next sibling line.
     * Returns null if no next sibling, the line otherwise.
     * The sibling is a title (Th, Tu or To), not a line (Lh nor Lu nor Lo)
     * @param  {line} line     The starting line for which we search a sibling
     * @param  {number} depthAbs [optional] If the siblings we search is not
     *                           of the same absolute depth
     * @return {line}          The next sibling if one, null otherwise
    ###
    _findNextSibling : (line, depth)->
        if !depth?
            depth = line.lineDepthAbs

        nextSib = line.lineNext
        loop    
            if nextSib == null or nextSib.lineDepthAbs < depth
                nextSib = null
                break
            else if nextSib.lineDepthAbs == depth && nextSib.lineType[0] == 'T'
                break
            nextSib = nextSib.lineNext
        return nextSib


    ###* -----------------------------------------------------------------------
     * Find the previous sibling line.
     * Returns null if no previous sibling, the line otherwise.
     * The sibling is a title (Th, Tu or To), not a line (Lh nor Lu nor Lo)
     * @param  {line} line     Rhe starting line for which we search a sibling
     * @param  {number} depthAbs [optional] If the siblings we search is not
     *                           of the same absolute depth
     * @return {line}          The previous sibling if one, null otherwise
    ###
    _findPrevSibling : (line, depth)->
        if !depth?
            depth = line.lineDepthAbs

        prevSib = line.linePrev
        loop    
            if prevSib == null or prevSib.lineDepthAbs < depth
                prevSib = null
                break
            else if prevSib.lineDepthAbs == depth && prevSib.lineType[0] == 'T'
                break
            prevSib = prevSib.linePrev
        return prevSib



    ###*
    # Delete the user multi line selection :
    #    * The 2 lines (selected of given in param) must be distinct
    #    * If no params :
    #        - @currentSel.theoricalRange will the range used to find the  
    #          lines to delete. 
    #        - Only the range is deleted, not the beginning of startline nor the
    #          end of endLine
    #        - the caret is positionned at the firts break point of range.
    #    * if startLine and endLine is given
    #       - the whole lines from start and endLine are deleted, both included.
    #       - the caret position is not modified
    # @param  {[line]} startLine [optional] if exists, the whole line will be deleted
    # @param  {[line]} endLine   [optional] if exists, the whole line will be deleted
    # @return {[none]}           [nothing]
    ###
    _deleteMultiLinesSelections : (startLine, endLine) ->
        
        # TODO  BJA : to remove when _moveLinesDown and _moveLinesUp will be
        # debugged
        if startLine == null or endLine == null
            throw new Error(
                'CEeditor._deleteMultiLinesSelections called with a null param'
                )

        # Get start and end positions of the selection.
        if startLine?
            range = rangy.createRange()
            selection.cleanSelection startLine, endLine, range
            replaceCaret = false
        else
            # currentSel has been updated by _keyDownCallBack
            # We don't use @currentSel.range because with chrome it might
            # not be in a text node...
            range          = @currentSel.theoricalRange
            startContainer = range.startContainer
            startOffset    = range.startOffset
            startLine      = @currentSel.startLine
            endLine        = @currentSel.endLine
            replaceCaret = true
            
        # Calculate depth for start and end line
        startLineDepth = startLine.lineDepthAbs
        endLineDepth   = endLine.lineDepthAbs
        deltaDepth     = endLineDepth - startLineDepth

        # Copy the un-selected end of endLine in a fragment
        endOfLineFragment = selection.cloneEndFragment range, endLine

        # Adapt end line type if needed.
        @_adaptEndLineType startLine, endLine, endLineDepth

        # Delete selection and adapt remaining parts consequently.
        range.deleteContents()

        # Insert the copied end of line at the end of startLine
        @_addMissingFragment startLine, endOfLineFragment

        # Remove endLine from this.lines and updates links
        @_removeEndLine startLine, endLine

        # Adapt depth
        @_adaptDepth startLine, startLineDepth, endLineDepth, deltaDepth

        # Place caret
        if replaceCaret
            @_setCaret(startContainer, startOffset)


    #  adapt the depth of the children and following siblings of end line
    #    in case the depth delta between start and end line is
    #    greater than 0, then the structure is not correct : we reduce
    #    the depth of all the children and siblings of endLine.
    #
    #  Then adapt the type of the first line after the children and siblings of
    #    end line. Its previous sibling or parent might have been deleted, 
    #    we then must find its new one in order to adapt its type.
    _adaptDepth: (startLine, startLineDepthAbs, endLineDepthAbs, deltaDepth) ->
        line = startLine.lineNext
        if line != null
            deltaDepth1stLine = line.lineDepthAbs - startLineDepthAbs
            if deltaDepth1stLine > 1
                while line!= null and line.lineDepthAbs >= endLineDepthAbs
                    newDepth = line.lineDepthAbs - deltaDepth
                    line.setDepthAbs(newDepth)
                    line = line.lineNext
                    
        if line != null
            # if the line is a line (Lx), then make it "independant"
            # by turning it in a Tx, except if unecessary (previou is same
            # type and same prof)
            if line.lineType[0] == 'L'
                if !(     startLine.lineType[1]  == line.lineType[1]      \
                      and startLine.lineDepthAbs == line.lineDepthAbs )
                    line.setType('T' + line.lineType[1])

            # find the previous sibling, adjust type to its type.
            firstLineAfterSiblingsOfDeleted = line
            depthSibling = line.lineDepthAbs
            
            while line != null and line.lineDepthAbs > depthSibling
                line = line.linePrev

            if line != null and line != firstLineAfterSiblingsOfDeleted
                prevSiblingType = line.lineType
                if firstLineAfterSiblingsOfDeleted.lineType != prevSiblingType
                    if prevSiblingType[1] == 'h'
                        @titleList(firstLineAfterSiblingsOfDeleted)
                    else
                        @markerList(firstLineAfterSiblingsOfDeleted)


    # Add back missing unselected fragment that have been deleted by our rough
    # deletion.
    # If startFrag et myEndLine are SPAN and they both have the same class
    # then we concatenate both
    _addMissingFragment: (line, fragment) ->
        startFrag = fragment.childNodes[0]
        lineEl = line.line$[0]

        if lineEl.lastChild is null
            node = document.createElement('span')
            lineEl.insertBefore(node,lineEl.firstChild)
        
        if lineEl.lastChild.nodeName is 'BR'
            lineEl.removeChild(lineEl.lastChild)
        lastNode = lineEl.lastChild

        if startFrag.tagName == lastNode.tagName == 'SPAN' and 
           startFrag.className == lastNode.className
            startOffset = lastNode.textContent.length
            newText = lastNode.textContent + startFrag.textContent
            lastNode.firstChild.textContent = newText
            fragment.removeChild(fragment.firstChild)
            lineEl.appendChild fragment
        else
            lineEl.appendChild fragment
            null


    # Remove end line and update line links of the start line.
    _removeEndLine: (startLine, endLine) ->
        startLine.lineNext = endLine.lineNext
        endLine.lineNext.linePrev = startLine if endLine.lineNext != null
        endLine.line$.remove()
        delete @_lines[endLine.lineID]


    # adapt the type of endLine and of its children to startLine 
    # the only useful case is when endLine must be changed from Th to Tu or To
    _adaptEndLineType: (startLine, endLine, endLineDepth) ->
        endLineType = endLine.lineType
        startLineType = startLine.lineType
        if endLineType[1] is 'h' and startLineType[1] isnt 'h'
            if endLineType[0] is 'L'
                endLine.setType('T' + endLineType[1])
            @markerList endLine


    # Put caret at given position. Regitser current selection.
    _setCaret: (startContainer, startOffset) ->
        range = rangy.createRange()
        range.collapseToPoint startContainer, startOffset
        @currentSel.sel.setSingleRange range
                

    ### ------------------------------------------------------------------------
    #  _insertLineAfter
    # 
    # Insert a line after a source line
    # The line will be inserted in the parent of the source line (which can be 
    # the editor or a fragment in the case of the paste for instance)
    # p = 
    #     sourceLine         : line after which the line will be added
    #     fragment           : [optionnal] - an html fragment that will be added
    #                          in the div of the line.
    #     innerHTML          : [optionnal] - if no fragment is given, an html
    #                          string that will be added to the new line.
    #     targetLineType     : type of the line to add
    #     targetLineDepthAbs : absolute depth of the line to add
    #     targetLineDepthRel : relative depth of the line to add
    ###
    _insertLineAfter : (p) ->
        newLine    = new Line(
                @                    , # editor
                p.targetLineType     , # type
                p.targetLineDepthAbs , # depth abs
                p.targetLineDepthRel , # depth relative
                p.sourceLine         , # previous line
                null                 , # next line
                p.fragment             # fragment
            )
        return newLine



    ### ------------------------------------------------------------------------
    #  _insertLineBefore
    # 
    # Insert a line before a source line
    # p = 
    #     sourceLine         : Line before which a line will be added
    #     fragment           : [optionnal] - an html fragment that will be added
    #                          the fragment is not supposed to end with a <br>
    #     targetLineType     : type of the line to add
    #     targetLineDepthAbs : absolute depth of the line to add
    #     targetLineDepthRel : relative depth of the line to add
    ###
    _insertLineBefore : (p) ->
        newLine    = new Line(
                @                    , # editor
                p.targetLineType     , # type
                p.targetLineDepthAbs , # depth abs
                p.targetLineDepthRel , # depth relative
                null                 , # previous line
                p.sourceLine         , # next line
                p.fragment             # fragment
            )
        return newLine


    ###  -----------------------------------------------------------------------
    #   _readHtml
    # 
    # Parse a raw html inserted in the iframe in order to update the controller
    ###
    _readHtml: () ->
        linesDiv$    = $(@linesDiv).children()  # linesDiv$= $[Div of lines]
        # loop on lines (div) to initialise the editor controler
        lineDepthAbs = 0
        lineDepthRel = 0
        lineID       = 0
        @_lines      = {}
        linePrev     = null
        lineNext     = null
        for htmlLine in linesDiv$
            htmlLine$ = $(htmlLine)
            lineClass = htmlLine$.attr('class') ? ""
            lineClass = lineClass.split('-')
            lineType  = lineClass[0]
            if lineType != ""
                lineDepthAbs_old = lineDepthAbs
                # hypothesis : _readHtml is called only on an html where 
                #              class="Tu-xx" where xx is the absolute depth
                lineDepthAbs     = +lineClass[1]
                deltaDepthAbs    = lineDepthAbs - lineDepthAbs_old
                lineDepthRel_old = lineDepthRel
                if lineType == "Th"
                    lineDepthRel = 0
                else
                    lineDepthRel = lineDepthRel_old + deltaDepthAbs
                lineID=(parseInt(lineID,10)+1)
                lineID_st = "CNID_"+lineID
                htmlLine$.prop("id",lineID_st)
                lineNew = new Line()
                lineNew.line$        = htmlLine$
                lineNew.lineID       = lineID_st
                lineNew.lineType     = lineType
                lineNew.lineDepthAbs = lineDepthAbs
                lineNew.lineDepthRel = lineDepthRel
                lineNew.lineNext     = null
                lineNew.linePrev     = linePrev
                # lineNew =
                #     line$        : htmlLine$
                #     lineID       : lineID_st
                #     lineType     : lineType
                #     lineDepthAbs : lineDepthAbs
                #     lineDepthRel : lineDepthRel
                #     lineNext     : null
                #     linePrev     : linePrev
                if linePrev != null then linePrev.lineNext = lineNew
                linePrev = lineNew
                @_lines[lineID_st] = lineNew
        @_highestId = lineID



    ### ------------------------------------------------------------------------
    # LINES MOTION MANAGEMENT
    # 
    # Functions to perform the motion of an entire block of lines
    # BUG : when doubleclicking on an end of line then moving this line
    #       down, selection does not behave as expected :-)
    # TODO: correct behavior when moving the second line up
    # TODO: correct behavior when moving the first line down
    # TODO: improve re-insertion of the line swapped with the block
    ####

    
    ### ------------------------------------------------------------------------
    # _moveLinesDown:
    #
    # -variables:
    #    linePrev                                       linePrev
    #    lineStart__________                            lineNext
    #    |.                 | The block                 lineStart_______
    #    |.                 | to move down      ==>     |.              |
    #    lineEnd____________|                           |.              |
    #    lineNext                                       lineEnd_________|
    #
    # -algorithm:
    #    1.delete lineNext with _deleteMultilinesSelections()
    #    2.insert lineNext between linePrev and lineStart
    #    3.if lineNext is more indented than linePrev, untab lineNext
    #      until it is ok
    #    4.else (lineNext less indented than linePrev), select the block
    #      (lineStart and some lines below) that is more indented than lineNext
    #      and untab it until it is ok
    ###
    _moveLinesDown : () ->
        
        # 0 - Set variables with informations on the selected lines
        sel   = @getEditorSelection()
        range = sel.getRangeAt(0)
        
        # TODO BJA : use findlines ?
        startDiv = selection.getLineDiv range.startContainer, range.startOffset
        endDiv = selection.getLineDiv range.endContainer, range.endOffset
        
        # Find first and last div corresponding to the first and last
        # selected lines
        startLineID = startDiv.id
        endLineID = endDiv.id
        
        lineStart = @_lines[startLineID]
        lineEnd   = @_lines[endLineID]
        linePrev  = lineStart.linePrev
        lineNext  = lineEnd.lineNext
            
        # if the last selected line (lineEnd) isnt the very last line
        if lineNext != null
            
            # 1 - save lineNext
            cloneLine = Line.clone(lineNext)
                
            # 2 - Delete lineNext content then restore initial selection
            # TODO BJA : ensure this call don't pass a null param
            @_deleteMultiLinesSelections(lineEnd, lineNext)
            
            # rangy.restoreSelection(savedSel)
            
            # 3 - Restore lineNext before the first selected line (lineStart)
            lineNext = cloneLine
            @_lines[lineNext.lineID] = lineNext
            
            # 4 - Modify the order of linking :
            #        linePrev--lineNext--lineStart--lineEnd
            lineNext.linePrev  = linePrev
            lineStart.linePrev = lineNext
            if lineNext.lineNext != null
                lineNext.lineNext.linePrev = lineEnd
            lineEnd.lineNext  = lineNext.lineNext
            lineNext.lineNext = lineStart
            if linePrev != null
                linePrev.lineNext = lineNext
            
            # 5 - Replace the lineNext line in the DOM
            lineStart.line$.before(lineNext.line$)
            
            # 6 - Re-insert lineNext after the end of the moved block.
            #     2 different configs of indentation may occur :
            
            if linePrev == null then return
                
            # 6.1 - The swapped line (lineNext) is less indented than
            #       the block's prev line (linePrev)
            if lineNext.lineDepthAbs <= linePrev.lineDepthAbs
                # find the last line to untab
                line = lineNext
                while (line.lineNext!=null and
                       line.lineNext.lineDepthAbs > lineNext.lineDepthAbs)
                    line = line.lineNext
                if line.lineNext != null
                    line = line.lineNext
                # select a block from first line to untab (lineStart)
                #                  to last  line to untab (line)
                myRange = rangy.createRange()
                myRange.setStart(lineStart.line$[0], 0)
                myRange.setEnd(line.line$[0], 0)
                # untab this selected block.
                numOfUntab = lineStart.lineDepthAbs-lineNext.lineDepthAbs
                if lineNext.lineNext.lineType[0]=='T'
                    # if linePrev is a 'T' and a 'T' follows, one untab less
                    if lineStart.lineType[0] == 'T'
                        numOfUntab -= 1
                    # if linePrev is a 'L' and a 'T' follows, one untab more
                    else
                        numOfUntab += 1
                
                while numOfUntab >= 0
                    @shiftTab(myRange)
                    numOfUntab -= 1
                    
            # 6.2 - The swapped line (lineNext) is more indented than
            #       the block's prev line (linePrev)
            else
                # untab lineNext
                myRange = rangy.createRange()
                myRange.setStart(lineNext.line$[0], 0)
                myRange.setEnd(lineNext.line$[0], 0)
                numOfUntab = lineNext.lineDepthAbs - linePrev.lineDepthAbs
                
                if lineStart.lineType[0]=='T'
                    # if lineEnd is a 'T' and a 'T' follows, one untab less
                    if linePrev.lineType[0]=='T'
                        numOfUntab -= 1
                    # if lineEnd is a 'L' and a 'T' follows, one untab more
                    else
                        numOfUntab += 1
                
                while numOfUntab >= 0
                    @shiftTab(myRange)
                    numOfUntab -= 1


    ### ------------------------------------------------------------------------
    # _moveLinesUp:
    #
    # -variables:
    #    linePrev                                   lineStart_________
    #    lineStart__________                        |.                |
    #    |.                 | The block             |.                |
    #    |.                 | to move up     ==>    lineEnd___________|
    #    lineEnd____________|                       linePrev
    #    lineNext                                   lineNext
    #
    # -algorithm:
    #    1.delete linePrev with _deleteMultilinesSelections()
    #    2.insert linePrev between lineEnd and lineNext
    #    3.if linePrev is more indented than lineNext, untab linePrev
    #      until it is ok
    #    4.else (linePrev less indented than lineNext), select the block
    #      (lineNext and some lines below) that is more indented than linePrev
    #      and untab it until it is ok
    ###
    _moveLinesUp : () ->
        
        # 0 - Set variables with informations on the selected lines
        sel   = @getEditorSelection()
        range = sel.getRangeAt(0)
        
        # TODO BJA : use findlines ?
        startDiv = selection.getLineDiv range.startContainer, range.startOffset
        endDiv = selection.getLineDiv range.endContainer, range.endOffset

        # Find first and last div corresponding to the first and last
        # selected lines
        startLineID = startDiv.id
        endLineID = endDiv.id
        
        lineStart = @_lines[startLineID]
        lineEnd   = @_lines[endLineID]
        linePrev  = lineStart.linePrev
        lineNext  = lineEnd.lineNext
 
        # if the first line selected (lineStart) isnt the very first line
        if linePrev != null
            
            # 0 - set boolean indicating if we are treating the second line
            isSecondLine = (linePrev.linePrev == null)
                        
            # 1 - save linePrev
            cloneLine = Line.clone(linePrev)
            
            # 2 - Delete linePrev content then restore initial selection
            # TODO BJA : ensure this call don't pass a null param
            @_deleteMultiLinesSelections(linePrev.linePrev, linePrev)
            
            # 3 - Restore linePrev below the last selected line (lineEnd )
            # 3.1 - if isSecondLine, line objects must be fixed
            if isSecondLine
                # remove the hidden element inserted by deleteMultiLines
                $(linePrev.line$[0].firstElementChild).remove()
                # add the missing BR
                linePrev.line$.append '<br>'
                lineStart.line$ = linePrev.line$
                lineStart.line$.attr('id', lineStart.lineID)
                @_lines[lineStart.lineID] = lineStart
                
            # 4 - Modify the order of linking:
            #        lineStart--lineEnd--linePrev--lineNext
            linePrev = cloneLine
            @_lines[linePrev.lineID] = linePrev
            
            linePrev.lineNext = lineNext
            lineEnd.lineNext  = linePrev
            if linePrev.linePrev != null
                linePrev.linePrev.lineNext = lineStart
            lineStart.linePrev = linePrev.linePrev
            linePrev.linePrev  = lineEnd
            if lineNext != null
                lineNext.linePrev = linePrev
                
            # 5 - Replace the linePrev line in the DOM
            lineEnd.line$.after(linePrev.line$)

            # 6 - Re-insert linePrev after the end of the moved block.
            #     2 different configs of indentation may occur :
            # 6.1 - The swapped line (linePrev) is less indented than the
            #       block's last line (lineEnd)
            if linePrev.lineDepthAbs <= lineEnd.lineDepthAbs and lineNext!=null
                # find last line to untab
                line = linePrev
                while (line.lineNext!=null and
                       line.lineNext.lineDepthAbs>linePrev.lineDepthAbs)
                    line = line.lineNext
                if line.lineNext != null
                    line = line.lineNext
                # select the block from first line to untab (lineNext)
                # to last  line to untab (line)
                myRange = rangy.createRange()
                myRange.setStart(lineNext.line$[0], 0)
                myRange.setEnd(line.line$[0], 0)
                # untab this selected block.
                numOfUntab = lineNext.lineDepthAbs - linePrev.lineDepthAbs
                if linePrev.lineNext.lineType[0] == 'T'
                    # if linePrev is a 'T' and a 'T' follows, one untab less
                    if linePrev.lineType[0]=='T'
                        numOfUntab -= 1
                    # if linePrev is a 'L' and a 'T' follows, one untab more
                    else
                        numOfUntab += 1
                
                while numOfUntab >= 0
                    @shiftTab(myRange)
                    numOfUntab -= 1
                    
            # 6.2 - The swapped line (linePrev) is more indented than
            #       the block's last line (lineEnd)
            else
                # untab linePrev
                myRange = rangy.createRange()
                myRange.setStart(linePrev.line$[0], 0)
                myRange.setEnd(linePrev.line$[0], 0)
                numOfUntab = linePrev.lineDepthAbs - lineEnd.lineDepthAbs
                
                if linePrev.lineType[0] == 'T'
                    # if lineEnd is a 'T' and a 'T' follows, one untab less
                    if lineEnd.lineType[0] == 'T'
                        numOfUntab -= 1
                    # if lineEnd is a 'L' and a 'T' follows, one untab more
                    else
                        numOfUntab += 1
                
                while numOfUntab >= 0
                    @shiftTab(myRange)
                    numOfUntab -= 1


    ###
    #  HISTORY MANAGEMENT:
    # 1. _addHistory (Save html code, selection markers, positions...)
    # 2. undoPossible (Return true only if unDo can be called)
    # 3. redoPossible (Return true only if reDo can be called)
    # 4. unDo (Undo the previous action)
    # 5. reDo ( Redo a undo-ed action)
    #
    # What is saved in the history:
    #  - current html content
    #  - current selection
    #  - current scrollbar position
    #  - the boolean newPosition
    ###

    ###
    #  _addHistory
    # 
    # Add html code and selection markers and scrollbar positions to the history
    ###
    _addHistory : () ->
        # 0 - mark selection
        savedSel = @saveEditorSelection()
        # save html selection
        @_history.historySelect.push savedSel
        # save scrollbar position
        savedScroll =
            xcoord: @editorBody$.scrollTop()
            ycoord: @editorBody$.scrollLeft()
        @_history.historyScroll.push savedScroll
        # save newPosition flag
        @_history.historyPos.push @newPosition
        # 1- add the html content with markers to the history
        @_history.history.push @linesDiv.innerHTML
        # 2 - update the index
        @_history.index = @_history.history.length - 1

    ### -------------------------------------------------------------------------
    #  undoPossible
    # Return true only if unDo can be called
    ###
    undoPossible : () ->
        return (@_history.index > 0)

    ### -------------------------------------------------------------------------
    #  redoPossible
    # Return true only if reDo can be called
    ###
    redoPossible : () ->
        return (@_history.index < @_history.history.length-2)

    ### -------------------------------------------------------------------------
    #  unDo :
    # Undo the previous action
    ###
    unDo : () ->
        # if there is an action to undo
        if @undoPossible()
            # if we are in an unsaved state
            if @_history.index == @_history.history.length-1
                # save current state
                @_addHistory()
                # re-evaluate index
                @_history.index -= 1

            # restore newPosition
            @newPosition = @_history.historyPos[@_history.index]
            # 0 - restore html
            @linesDiv.innerHTML = @_history.history[@_history.index]
            # 1 - restore selection
            savedSel = @_history.historySelect[@_history.index]
            rangy.deserializeSelection savedSel, @linesDiv
            # 2 - restore scrollbar position
            xcoord = @_history.historyScroll[@_history.index].xcoord
            ycoord = @_history.historyScroll[@_history.index].ycoord
            @editorBody$.scrollTop(xcoord)
            @editorBody$.scrollLeft(ycoord)
            # 3 - restore the lines structure
            @_readHtml()
            # 4 - update the index
            @_history.index -= 1

    ### -------------------------------------------------------------------------
    #  reDo :
    # Redo a undo-ed action
    ###
    reDo : () ->
        # if there is an action to redo
        if @redoPossible()
            # restore newPosition
            @newPosition = @_history.historyPos[@_history.index+1]
            # 0 - update the index
            @_history.index += 1
            # 1 - restore html
            @linesDiv.innerHTML = @_history.history[@_history.index+1]
            # 2 - restore selection
            savedSel = @_history.historySelect[@_history.index+1]
            savedSel.restored = false
            rangy.restoreSelection(savedSel)
            # 3 - restore scrollbar position
            xcoord = @_history.historyScroll[@_history.index+1].xcoord
            ycoord = @_history.historyScroll[@_history.index+1].ycoord
            @editorBody$.scrollTop(xcoord)
            @editorBody$.scrollLeft(ycoord)
            # 4 - restore lines structure
            @_readHtml()


    ### ------------------------------------------------------------------------
    # EXTENSION  :  auto-summary management and upkeep
    # 
    # initialization
    # TODO: avoid updating the summary too often
    #       it would be best to make the update faster (rather than reading
    #       every line)
    ###
    _initSummary : () ->
        summary = @editorBody$.children("#navi")
        if summary.length == 0
            summary = $ document.createElement('div')
            summary.attr('id', 'navi')
            summary.prependTo @editorBody$
        return summary
        
    # Summary upkeep
    _buildSummary : () ->
        summary = @initSummary()
        @editorBody$.children("#navi").children().remove()
        lines = @_lines
        for c of lines
            if (@editorBody$.children("#" + "#{lines[c].lineID}").length > 0 and lines[c].lineType == "Th")
                lines[c].line$.clone().appendTo summary


    ### ------------------------------------------------------------------------
    #  EXTENSION  :  DECORATION FUNCTIONS (bold/italic/underlined/quote)
    #  TODO
    ###

    
    ### ------------------------------------------------------------------------
    #  PASTE MANAGEMENT
    # 0 - save selection
    # 1 - move the cursor into an invisible sandbox
    # 2 - redirect pasted content in this sandox
    # 3 - sanitize and adapt pasted content to the editor's format
    # 4 - restore selection
    # 5 - insert cleaned content is behind the cursor position
    ###
    paste : (event) ->
        # init the div where the paste will actualy accur. 
        mySandBox = @clipboard
        # save current selection in this.currentSel
        @updateCurrentSelIsStartIsEnd()
        # move caret into the sandbox
        range = rangy.createRange()
        range.selectNodeContents mySandBox
        sel = @getEditorSelection()
        sel.setSingleRange range
        range.detach()
        # check whether the browser is a Webkit or not
        if event and event.clipboardData and event.clipboardData.getData
            # Webkit: 1 - get data from clipboard
            #         2 - put data in the sandbox
            #         3 - clean the sandbox
            #         4 - cancel event (otherwise it pastes twice)
            
            if event.clipboardData.types == "text/html"
                mySandBox.innerHTML = event.clipboardData.getData('text/html')
            else if event.clipboardData.types == "text/plain"
                mySandBox.innerHTML = event.clipboardData.getData('text/plain')
            else
                mySandBox.innerHTML = ""
            @_waitForPasteData mySandBox
            if event.preventDefault
                event.stopPropagation()
                event.preventDefault()
            return false
        else
            # not a Webkit: 1 - empty the sandBox
            #               2 - paste in sandBox
            #               3 - cleanup the sandBox
            # mySandBox.innerHTML = ""
            @_waitForPasteData mySandBox
            return true



    ###*
    # * init the div where the browser will actualy paste.
    # * this method is called after each refresh of the content of the editor (
    # * replaceContent, deleteContent, setEditorContent)
    # * TODO : should be called just once at editor init : for this the editable
    # * content shouldn't be directly in the body of the iframe but in a div.
    # * @return {obj} a ref to the clipboard div
    ###
    _initClipBoard : () ->
        clipboardEl = document.createElement('div')
        clipboardEl.setAttribute('contenteditable','true')
        @clipboard$ = $ clipboardEl
        @clipboard$.attr('id', 'editor-clipboard')
        getOffTheScreen =
            left: -300
        @clipboard$.offset getOffTheScreen
        @clipboard$.prependTo @editorBody$
        @clipboard = @clipboard$[0]
        @clipboard.style.setProperty('width','280px')
        @clipboard.style.setProperty('position','fixed')
        @clipboard.style.setProperty('overflow','hidden')
        @clipboard
    


    ###*
     * Function that will call itself until the browser has pasted data in the
     * clipboar div
     * @param  {element} sandbox      the div where the browser will paste data
     * @param  {function} processpaste the function to call back whan paste 
     * is ok
    ###
    _waitForPasteData : =>
    # if the clipboard div has child => paste is done => can continue
        if @clipboard.childNodes and @clipboard.childNodes.length > 0
            @_processPaste()
        # else : paste not ready => wait
        else
            setTimeout @_waitForPasteData, 100
       


    ###
     * Called when the browser has pasted data in the clipboard div. 
     * Its role is to insert the content of the clipboard into the editor.
     * @param  {element} sandbox 
    ###

    _processPaste : () =>
        sandbox = @.clipboard
        currSel = @currentSel
        
        # 1- Sanitize clipboard content with node-validator 
        # (https://github.com/chriso/node-validator)
        # may be improved with google caja sanitizer :
        # http://code.google.com/p/google-caja/wiki/JsHtmlSanitizer
        sandbox.innerHTML = sanitize(sandbox.innerHTML).xss()
        
        # 2- Prepare a fragment where the lines (<div id="CNID_xx" ... </div>)
        # will be prepared before to be inserted in the editor.
        # _insertLineAfter() will work to insert new lines in the frag and 
        # will correctly update the editor. For that we insert a dummyLine 
        # at the beginning so that the first insertLineAfter works.
        frag = document.createDocumentFragment()
        dummyLine =
            lineNext : null
            linePrev : null
            line$    : $("<div id='dummy' class='Tu-1'></div>")
        frag.appendChild(dummyLine.line$[0])

        # 3- _domWalk will parse the clipboard in order to insert lines in frag.
        # Each line will be prepared in its own fragment before being inserted
        # into frag.
        # _domWalk is recursive and the variables of the context of the parse 
        # are stored in the parameter "domWalkContext" that is transmited at
        # each recursion.
        currentLineFrag = document.createDocumentFragment()
        absDepth = currSel.startLine.lineDepthAbs
        if currSel.startLine.lineType == 'Th'
            absDepth += 1
        domWalkContext =
            # The fragment where new lines will be added during the parse of the
            # clipboard div
            frag               : frag,
            # Refers to the last inserted line in the frag
            lastAddedLine      : dummyLine,
            # Fragment where a line is under construction
            currentLineFrag    : currentLineFrag,
            # Element (or node) of currentLineFrag being populated by _domWalk
            currentLineEl      : currentLineFrag,
            # Absolute depth of the current explored node of clip board
            absDepth           : absDepth,
            # Level of the Previous  <hx> element (ex : if last title parsed 
            # was h3 => prevHxLevel==3)
            prevHxLevel        : null,
            # Previous Cozy Note Line Abs Depth, used for the insertion of 
            # internal lines with  _clipBoard_Insert_InternalLine()
            prevCNLineAbsDepth : null,
            # Boolean wether currentLineFrag has already had an 
            # element appended.
            isCurrentLineBeingPopulated : false

        # go for the walk !
        htmlStr = @_domWalk sandbox, domWalkContext
        
        # empty the clipboard div
        sandbox.innerHTML = ""
        # delete dummy line from the fragment
        frag.removeChild(frag.firstChild)

        ###
        # TODO : the following steps removes all the styles of the lines in frag
        # Later this will be removed in order to take into account styles.
        ###
        # for line in frag.childNodes.length
        #     line = frag.childNodes[i]
        #     txt = line.textContent
        #     line.innerHTML = '<span></span><br>'
        #     line.firstChild.appendChild(document.createTextNode(txt))
        ###
        # END TODO
        ###

        # 4- Delete the selections so that the selection is collapsed
        startLine = currSel.startLine
        endLine   = currSel.endLine
        if currSel.range.collapsed
            # nothing to do
        else if endLine == startLine
            currSel.range.deleteContents()
            # in case deleteContent left a span without text node
            selection.normalize(currSel.range)
        else
            @_deleteMultiLinesSelections()
            selection.normalize(currSel.range) 
            @newPosition = true # in order to force normalization
            currSel = @updateCurrentSelIsStartIsEnd()
            @newPosition = false
            startLine = currSel.startLine

        ### 5- Insert first line of the frag in the target line
        # We assume that the structure of lines in frag and in the editor are :
        #   <div><span>(TextNode)</span><br></div>
        # what will be incorrect when styles will be taken into account.
        # 
        ###
        # a text node because of selection.normalize()
        targetNode   = currSel.range.startContainer 
        startOffset  = currSel.range.startOffset
        # except if we are in chrome : normalise can't work in empty line, so we
        # have to get the theorical breakpoint where the selection should be.
        if @isChromeOrSafari && targetNode.nodeName != '#text'
            breakPoint = selection.normalizeBP(targetNode, startOffset)
            targetNode = breakPoint.cont
            startOffset = breakPoint.offset

        endOffset = targetNode.length - startOffset
        # prepare lineElements
        if frag.childNodes.length > 0
            lineElements = Array.prototype.slice.call(frag.firstChild.childNodes)
        else
            lineElements = [frag]
        # loop on each element to insert (only one for now)
        for elToInsert in lineElements
            @_insertElement
            # If targetNode & elToInsert are SPAN or TextNode and both have 
            # the same class, then we concatenate them
            if (elToInsert.tagName=='SPAN')
                if (targetNode.tagName=='SPAN' or targetNode.nodeType==Node.TEXT_NODE )
                    targetText   = targetNode.textContent
                    newText      = targetText.substr(0,startOffset)
                    newText     += elToInsert.textContent
                    newText     += targetText.substr(startOffset)
                    targetNode.textContent = newText
                    startOffset += elToInsert.textContent.length
                else if targetNode.tagName=='A'
                    targetNode.parentElement.insertBefore(elToInsert,targetNode.nextSibling)
                    targetNode = targetNode.parentElement
                    startOffset = $(targetNode).children().index(elToInsert) + 1
                else if targetNode.tagName=='DIV'
                    targetNode.insertBefore(elToInsert,targetNode[startOffset])
                    startOffset += 1

            else if (elToInsert.tagName=='A')
                if targetNode.nodeName=='#text'
                    parent = targetNode.parentElement
                    parent.parentElement.insertBefore(elToInsert,parent.nextSibling)
                    targetNode = parent.parentElement
                    startOffset = $(targetNode).children().index(elToInsert) + 1
                else if targetNode.tagName in ['SPAN' ,'A']
                    targetNode.parentElement.insertBefore(elToInsert,targetNode.nextSibling)
                    targetNode = targetNode.parentElement
                    startOffset = $(targetNode).children().index(elToInsert) + 1
                else if targetNode.tagName == 'DIV'
                    targetNode.insertBefore(elToInsert,targetNode[startOffset])
                    startOffset += 1

        ###
        # 6- If the clipboard has more than one line, insert the end of target
        #    line in the last line of frag and delete it
        ###
        if frag.childNodes.length > 1
            range = document.createRange()
            range.setStart(targetNode,startOffset)
            parendDiv = targetNode
            while parendDiv.tagName != 'DIV'
                parendDiv = parendDiv.parentElement
            range.setEnd(parendDiv,parendDiv.children.length-1)
            endTargetLineFrag = range.extractContents()
            range.detach()
            this._insertFrag(
                frag.lastChild,                    # last line of frag
                frag.lastChild.children.length-1,  # penultimate node of last line
                endTargetLineFrag)                 # the frag to insert
            # TODO : the next 3 lines are required for firebug to detect
            # breakpoints ! ! !   ???????? (otherwise could be deleted)
            parendDiv = targetNode
            while parendDiv.tagName != 'DIV'
                parendDiv = parendDiv.parentElement
        ###*
         * remove the firstAddedLine from the fragment
        ###
        firstAddedLine = dummyLine.lineNext
        secondAddedLine = firstAddedLine?.lineNext
        if frag.firstChild?
            frag.removeChild(frag.firstChild)
        if firstAddedLine?
            delete this._lines[firstAddedLine.lineID]

        ###*
         * 7- updates nextLine and prevLines, insert frag in the editor
        ###
        if secondAddedLine?
            lineNextStartLine          = currSel.startLine.lineNext
            currSel.startLine.lineNext = secondAddedLine
            secondAddedLine.linePrev   = currSel.startLine
            if lineNextStartLine == null
                @linesDiv.appendChild(frag)
            else
                domWalkContext.lastAddedLine.lineNext = lineNextStartLine
                lineNextStartLine.linePrev = domWalkContext.lastAddedLine
                @linesDiv.insertBefore(frag, lineNextStartLine.line$[0])
        ###*
         * 8- position caret
        ###
        if secondAddedLine?
            # Assumption : last inserted line always has at least one <span> with only text inside
            caretTextNodeTarget = lineNextStartLine.linePrev.line$[0].childNodes[0].firstChild
            caretOffset = caretTextNodeTarget.length - endOffset
            currSel.sel.collapse(caretTextNodeTarget, caretOffset)
        else
            currSel.sel.collapse(targetNode, startOffset)



    ###*
     * Insert a frag in a node container at startOffset
     * ASSERTION : 
     * TODO : this method could be also used in _deleteMultiLinesSelections 
     * especialy if _insertFrag optimizes the insertion by fusionning cleverly
     * the elements
     * @param  {Node} targetContainer the node where to make the insert
     * @param  {Integer} targetOffset    the offset of insertion in targetContainer
     * @param  {fragment} frag           the fragment to insert
     * @return {nothing}                nothing
    ###
    _insertFrag : (targetContainer, targetOffset, frag) ->

        if targetOffset == 0
            range = document.createRange()
            range.setStart(startContainer,startOffset)
            range.setEnd(startContainer,startOffset)
            range.insertNode(frag)
            range.detach()
        else
            if frag.childNodes.length>0
                targetNode = targetContainer.childNodes[targetOffset-1]
                targetNode.textContent += frag.firstChild.textContent


    ###*
     * Walks thoug an html tree in order to convert it in a strutured content
     * that fit to a note structure.
     * @param  {html element} elemt   Reference to an html element to be parsed
     * @param  {object} context _domWalk is recursive and its context of execution
     *                  is kept in this param instead of using the editor context
     *                  (quicker and better) isolation
    ###
    _domWalk : (elemt, context) ->
        this.__domWalk(elemt, context)
        # if a line was being populated, append it to the frag
        if context.currentLineFrag.childNodes.length > 0
            p =
                sourceLine         : context.lastAddedLine
                fragment           : context.currentLineFrag
                targetLineType     : "Tu"
                targetLineDepthAbs : context.absDepth
                targetLineDepthRel : context.absDepth
            context.lastAddedLine = @_insertLineAfter(p)


    ###*
     * Walks thoug an html tree in order to convert it in a strutured content
     * that fit to a note structure.
     * @param  {html element} nodeToParse   Reference to an html element to 
     *                        be parsed
     * @param  {object} context __domWalk is recursive and its context of 
     *                          execution is kept in this param instead of 
     *                          using the editor context (quicker and better) 
     *                          isolation
    ###
    __domWalk : (nodeToParse, context) ->
        absDepth    = context.absDepth
        prevHxLevel = context.prevHxLevel
        
        # loop on the child nodes of the parsed node
        for child in nodeToParse.childNodes
            switch child.nodeName

                when '#text'
                    # text nodes are inserted in the current populated 
                    # element if its a "textual" element
                    if context.currentLineEl.nodeName in ['SPAN','A']
                        context.currentLineEl.textContent += child.textContent
                    # otherwise in a new span
                    else
                        txtNode = document.createTextNode(child.textContent)
                        spanEl = document.createElement('span')
                        spanEl.appendChild txtNode
                        context.currentLineEl.appendChild spanEl
                    
                    context.isCurrentLineBeingPopulated = true

                when 'P', 'UL', 'OL'
                    # we have to insert the current line and create a new on for
                    # the content of this child.
                    context.absDepth = absDepth
                    @__domWalk(child,context )
                    if context.isCurrentLineBeingPopulated
                        @_appendCurrentLineFrag(context,absDepth,absDepth)

                when 'H1','H2','H3','H4','H5','H6'
                    # if prevHxLevel == null
                    #     prevHxLevel = +child.nodeName[1]-1
                    # newHxLevel = +child.nodeName[1]
                    # deltaHxLevel = newHxLevel-prevHxLevel
                    deltaHxLevel =0

                    @__domWalk(child, context)
                    # if a line was being populated, append it to the frag
                    if context.isCurrentLineBeingPopulated
                        @_appendCurrentLineFrag(context,
                                                Math.min(0,deltaHxLevel) + absDepth,
                                                Math.min(0,deltaHxLevel) + absDepth
                            )

                    # TODO : for depth
                    # if deltaHxLevel > 0
                    #     absDepth             = absDepth+1
                    #     context.absDepth     = absDepth
                    #     prevHxLevel          = newHxLevel
                    #     context.prevHxLevel  = newHxLevel
                    # else 
                    #     absDepth             = absDepth+deltaHxLevel+1 # TODO put a min
                    #     context.absDepth     = absDepth
                    #     prevHxLevel          = newHxLevel
                    #     context.prevHxLevel  = newHxLevel

                when 'LI'
                    # if a line was being populated, append it to the frag
                    if context.isCurrentLineBeingPopulated
                        @_appendCurrentLineFrag(context,absDepth,absDepth)
                    # walk throught the child and append it to the frag
                    @__domWalk(child, context)
                    if context.isCurrentLineBeingPopulated
                        @_appendCurrentLineFrag(context,absDepth,absDepth)

                when 'TR'
                    # if a line was being populated, append it to the frag
                    if context.isCurrentLineBeingPopulated
                        @_appendCurrentLineFrag(context,absDepth,absDepth)
                    # walk throught the child and append it to the frag
                    @__domWalk(child, context)
                    if context.isCurrentLineBeingPopulated
                        @_appendCurrentLineFrag(context,absDepth,absDepth)

                when 'BR'
                    # append the line that was being populated to the frag (even
                    # if this one had not yet been populated by any element)
                    @_appendCurrentLineFrag(context,absDepth,absDepth)
                
                when 'A'
                    # without <a> element :
                    # lastInsertedEl = context.currentLineEl.lastChild
                    # if lastInsertedEl != null and lastInsertedEl.nodeName=='SPAN'
                    #     lastInsertedEl.textContent += '[' + child.textContent + ']('+ child.href+')'
                    # else
                    #     spanNode = document.createElement('span')
                    #     spanNode.textContent = child.textContent + ' [[' + child.href+']] '
                    #     context.currentLineEl.appendChild(spanNode)
                    # context.isCurrentLineBeingPopulated = true
                    
                    # with <a> element :
                    aNode = document.createElement('a')
                    aNode.textContent = child.textContent
                    aNode.href        = child.href
                    context.currentLineEl.appendChild(aNode)


                    # if context.currentLineEl.nodeName == 'A'
                    #     context.currentLineEl.textContent += child.textContent
                    # # otherwise in a new span
                    # else
                    #     txtNode = document.createTextNode(child.textContent)
                    #     spanEl = document.createElement('span')
                    #     spanEl.appendChild txtNode
                    #     context.currentLineEl.appendChild spanEl
                    
                    # context.isCurrentLineBeingPopulated = true


                # ###
                # ready for styles to be taken into account
                # when 'A'
                #     # insert a <a> in the currentLineFrag
                #     aNode = document.createElement('a')
                #     initialCurrentLineEl = context.currentLineEl
                #     context.currentLineEl.appendChild(aNode)
                #     context.currentLineEl = aNode
                #     @__domWalk(child, context)
                #     context.currentLineEl = initialCurrentLineEl
                #     context.isCurrentLineBeingPopulated = true
                # when 'B','STRONG'
                #     # insert a <span> in the currentLineFrag
                #     spanNode = document.createElement('strong')
                #     initialCurrentLineEl = context.currentLineEl
                #     context.currentLineEl.appendChild(spanNode)
                #     context.currentLineEl = spanNode
                #     result += @__domWalk(child, context)
                #     context.currentLineEl = initialCurrentLineEl
                #     context.isCurrentLineBeingPopulated = true
                # when 'I','EM'
                #     # insert a <span> in the currentLineFrag
                #     spanNode = document.createElement('EM')
                #     initialCurrentLineEl = context.currentLineEl
                #     context.currentLineEl.appendChild(spanNode)
                #     @__domWalk(child, context)
                #     context.currentLineEl = initialCurrentLineEl
                #     context.isCurrentLineBeingPopulated = true
                # when 'SPAN'
                #     # insert a <span> in the currentLineFrag
                #     spanNode = document.createElement('span')
                #     initialCurrentLineEl = context.currentLineEl
                #     context.currentLineEl = spanNode
                #     context.currentLineFrag.appendChild(spanNode)
                #     @__domWalk(child, context)
                #     context.currentLineEl = initialCurrentLineEl
                #     context.isCurrentLineBeingPopulated = true
                when 'DIV', 'TABLE', 'TBODY'
                    if child.id.substr(0,5)=='CNID_'
                        @_clipBoard_Insert_InternalLine(child, context)
                    else
                        @__domWalk(child, context)
                else
                    lastInsertedEl = context.currentLineEl.lastChild
                    if lastInsertedEl != null and lastInsertedEl.nodeName=='SPAN'
                        lastInsertedEl.textContent += child.textContent
                    else
                        spanNode = document.createElement('span')
                        spanNode.textContent = child.textContent
                        context.currentLineEl.appendChild(spanNode)
                    context.isCurrentLineBeingPopulated = true

        true



    ###*
     * Append to frag the currentLineFrag and prepare a new empty one.
     * @param  {Object} context  [description]
     * @param  {Number} absDepth absolute depth of the line to insert
     * @param  {Number} relDepth relative depth of the line to insert
    ###
    _appendCurrentLineFrag : (context,absDepth,relDepth) ->
        # if the line is empty, add an empty Span before the <br>
        if context.currentLineFrag.childNodes.length == 0
            spanNode = document.createElement('span')
            spanNode.appendChild(document.createTextNode(''))
            context.currentLineFrag.appendChild(spanNode)

        p =
            sourceLine         : context.lastAddedLine
            fragment           : context.currentLineFrag
            targetLineType     : "Tu"
            targetLineDepthAbs : absDepth
            targetLineDepthRel : relDepth
        context.lastAddedLine = @_insertLineAfter(p)
        # prepare the new lingFrag & lineEl
        context.currentLineFrag = document.createDocumentFragment()
        context.currentLineEl = context.currentLineFrag
        context.isCurrentLineBeingPopulated = false



    ###*
     * Insert in the editor a line that was copied in a cozy note editor
     * @param  {html element} elemt a div ex : <div id="CNID_7" class="Lu-3"> ... </div>
     * @return {line}        a ref to the line object
    ###
    _clipBoard_Insert_InternalLine : (elemt, context)->
        lineClass = elemt.className.split('-')
        lineDepthAbs = +lineClass[1]
        lineClass = lineClass[0]
        if !context.prevCNLineAbsDepth
            context.prevCNLineAbsDepth = lineDepthAbs
        deltaDepth = lineDepthAbs - context.prevCNLineAbsDepth
        if deltaDepth > 0
            # context.absDepth += 1
        else
            # context.absDepth += deltaDepth
        elemtFrag = document.createDocumentFragment()
        n = elemt.childNodes.length
        i = 0
        while i < n 
            elemtFrag.appendChild(elemt.childNodes[0])
            i++
        p =
            sourceLine         : context.lastAddedLine
            fragment           : elemtFrag
            targetLineType     : "Tu"
            targetLineDepthAbs : context.absDepth
            targetLineDepthRel : context.absDepth
        context.lastAddedLine = @_insertLineAfter(p)

        
  
    ### ------------------------------------------------------------------------
    # EXTENSION  :  cleaned up HTML parsing
    #
    #  (TODO)
    # 
    # We suppose the html treated here has already been sanitized so the DOM
    #  structure is coherent and not twisted
    # 
    # _parseHtml:
    #  Parse an html string and return the matching html in the editor's format
    # We try to restitute the very structure the initial fragment :
    #   > indentation
    #   > lists
    #   > images, links, tables... and their specific attributes
    #   > text
    #   > textuals enhancements (bold, underlined, italic)
    #   > titles
    #   > line return
    # 
    # Ideas to do that :
    #  0- textContent is always kept
    #  1- A, IMG keep their specific attributes
    #  2- UL, OL become divs whose class is Tu/To. LI become Lu/Lo
    #  3- H[1-6] become divs whose class is Th. Depth is determined depending on
    #     where the element was pasted.
    #  4- U, B have the effect of adding to each elt they contain a class (bold
    #     and underlined class)
    #  5- BR delimit the different DIV that will be added
    #  6- relative indentation preserved with imbrication of paragraphs P
    #  7- any other elt is turned into a simple SPAN with a textContent
    #  8- IFRAME, FRAME, SCRIPT are ignored
    ####
    
    # _parseHtml : (htmlFrag) ->
        
        # result = ''

        # specific attributes of IMG and A are copied
        # copySpecificAttributes =
            # "IMG" : (elt) ->
                # attributes = ''
                # for attr in ["alt", "border", "height", "width", "ismap", "hspace", "vspace", "logdesc", "lowsrc", "src", "usemap"]
                    # if attr?
                        # attributes += " #{attr}=#{elt.getAttribute(attr)}"
                # return "<img #{attributes}>#{elt.textContent}</img>"
            # "A" : (elt) ->
                # attributes = ''
                # for attr in ["href", "hreflang", "target", "title"]
                    # if attr?
                        # attributes += " #{attr}=#{elt.getAttribute(attr)}"
                # return "<a #{attributes}>#{elt.textContent}</a>"
                

        # read recursively through the dom tree and turn the html fragment into
        # a correct bit of html for the editor with the same specific attributes
        
        # leafReader = (tree) ->
            # if the element is an A or IMG --> produce an editor A or IMG
            # if tree.nodeName == "A" || tree.nodeName == "IMG"
                # return copySpecificAttributes[tree.nodeName](tree)
            # if the element is a BR
            # else if tree.nodeName == "BR"
                # return "<br>"
            # if the element is B, U, I, EM then spread this highlightment
            # if the element is UL(OL) then start a Tu(To)
            # if the element is LI then continue the list (unless if it is the
            #    first child of a UL-OL)
            # else
            # else if tree.firstChild != null
                # sibling = tree.firstChild
                # while sibling != null
                   #  result += leafReader(sibling)
                    # sibling = sibling.nextSibling
            # if the element
                # src = "src=#{tree.getAttribute('src')}"
            
            # if the element has children
            # child = tree.firstChild
            # if child != null
            #     while child != null
                    # result += leafReader(child)
                    # child = child.nextSibling
            # else
                
                # return tree.innerHTML || tree.textContent

        # leafReader(htmlFrag)

    # Debug purpose only
    logKeyPress: (e) ->
        #console.clear()
        #console.log '__keyPressListener____________________________'
        #console.log e
        #console.log "ctrl #{e.ctrlKey}; Alt #{e.altKey}; Shift #{e.shiftKey}; "
        #console.log "which #{e.which}; keyCode #{e.keyCode}"
        #console.log "metaKeyStrokesCode:'#{metaKeyStrokesCode}' keyStrokesCode:'#{keyStrokesCode}'"

CNeditor = exports.CNeditor
