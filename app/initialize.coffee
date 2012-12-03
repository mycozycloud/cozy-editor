
# Load librairies used in the app
require '../lib/app_helpers'
{beautify} = require('views/beautify')
{CNeditor} = require('views/CNeditor/CNeditor')
{AutoTest} = require('views/autoTest')



###****************************************************
 * 0 - INITIALIZE APP
###

$("body").html require './views/templates/editor'
editorIframe$ = $("iframe")

# $("iframe").on "onHistoryChanged", (e) ->
    # console.log "history updated"
# $("iframe").on "onKeyUp", (e) ->
    # console.log "history not updated"


###****************************************************
 * 1 - EDITOR CALL BACK
 * 
 * callback to execute after editor's initialization 
 * the contexte (this) inside the function is the editor
###
cb = () ->

    #### -------------------------------------------------------------------
    ### initialize content of the editor
    this.replaceContent( require('views/templates/content-empty') )
    this.replaceContent( require('views/templates/content-full') )
    this.replaceContent( require('views/templates/content-full-marker') )
    this.replaceContent( require('views/templates/content-shortlines-marker') )
    this.replaceContent( require('views/templates/content-full-relative-indent') )
    this.replaceContent( require('views/templates/content-shortlines-all-hacked') )
    this.deleteContent()
    ###
    this.replaceContent( require('views/templates/content-shortlines-all') )

    #### -------------------------------------------------------------------
    # buttons init, beautify actions
    editorCtrler = this
    editorBody$  = this.editorBody$

    beautify(editorBody$)
    
    editorBody$.on 'keyup' , ->
        beautify(editorBody$)
        
    $("#resultBtnBar_coller").on  'click' , ->
        beautify(editorBody$)
        
    $("#printRangeBtn").on "click", () ->
        sel = editorCtrler.getEditorSelection()
        i = 0
        l = sel.rangeCount
        while i<l
            console.log "Range N°#{i}"
            range = sel.getRangeAt(i)
            console.log range
            console.log "content : #{range.toHtml()}"
            i++
            
    # Allows user to load a file in the Cozy format
    $('#contentSelect').on "change" , (e) ->
        console.log "views/templates/#{e.currentTarget.value}"
        editorCtrler.replaceContent( require("views/templates/#{e.currentTarget.value}") )
        beautify(editorBody$)

    # Allows user to load a style sheet for the page
    $('#cssSelect').on "change" , (e) ->
        editorCtrler.replaceCSS( e.currentTarget.value )

    #### -------------------------------------------------------------------
    # Buttons for the editor
    # Buttons should probably give back the focus to the editor's iframe
    $("#indentBtn").on "click", () ->
        editorCtrler.tab()
    $("#unIndentBtn").on "click", () ->
        editorCtrler.shiftTab()
    $("#markerListBtn").on "click", () ->
        editorCtrler.markerList()
    $("#titleBtn").on "click", () ->
        editorCtrler.titleList()
    $("#clearBtn").on "click", () ->
        editorCtrler.deleteContent()
    $("#undoBtn").on "click", () ->
        editorCtrler.unDo()
    $("#redoBtn").on "click", () ->
        editorCtrler.reDo()
        
    #### -------------------------------------------------------------------
    # Special buttons (to be removed later)
    #  > tests the code structure
    checker = new AutoTest()
    $("#checkBtn").on "click", () ->
        res = checker.checkLines(editorCtrler)
        date = new Date()
        st = date.getHours()+":"+date.getMinutes()+":"+date.getSeconds()+" - "
        if res
            $("#resultText").val(st+"Syntax test success")
        else
            $("#resultText").val(st+"Syntax test FAILLURE : cf logs")
    #  > translate cozy code into markdown and markdown to cozy code
    #    Note: in the markdown code there should be two \n between each line
    $("#markdownBtn").on "click", () ->
        $("#resultText").val(editorCtrler._cozy2md $("#resultText").val())
    $("#cozyBtn").on "click", () ->
        $("#resultText").val(editorCtrler._md2cozy $("#resultText").val())
    $("#addClass").toggle(
        () ->
            addClassToLines("sel")
        () ->
            removeClassFromLines("sel")
        )
    #$("#summaryBtn").on "click", () ->
    #    editorCtrler.buildSummary()

    #### -------------------------------------------------------------------
    # Returns an object containing every selected line in the iframe
    getSelectedLines = (sel) ->
        myDivs = []             # Array containing each selected DIV
        if sel.rangeCount == 0
            return
        #_For each selected area
        for i in [0..sel.rangeCount-1]
            range = sel.getRangeAt(i)
            #_Case of multiline selection (includes always at least one div)
            divs = range.getNodes([1], (element) -> element.nodeName=='DIV')
            #_If a single DIV is selected
            if divs.length == 0
                # (bug-counter) the whole body can be "selected"
                if range.commonAncestorContainer.nodeName != 'BODY'
                    node = range.commonAncestorContainer
                    if node.nodeName != 'DIV'
                        node = $(node).parents("div")[0]
                    divs.push node
            # We fill myDivs with the encountered DIV
            k = 0
            while k < divs.length
                myDivs.push $(divs[k])
                k++
        return myDivs

        
    #### -------------------------------------------------------------------
    # Add class at beginning of lines
    addClassToLines = (mode) =>
        sel = rangy.getIframeSelection(this.editorIframe)
        if mode == "sel"
            lines = getSelectedLines(sel)
            k = 0
            while k < lines.length
                div = lines[k]
                div.attr('toDisplay', div.attr('class') + '] ')
                k++
        else
            lines = this._lines
            for lineID of lines
                div = $ lines[lineID].line$[0]
                div.attr('toDisplay', div.attr('class') + '] ')

    #### -------------------------------------------------------------------
    # Remove class from beginning of lines
    removeClassFromLines = (mode) =>
        sel = rangy.getIframeSelection(this.editorIframe)
        if mode == "sel"
            lines = getSelectedLines(sel)
            k = 0
            while k < lines.length
                div = lines[k]
                div.attr('toDisplay', '')
                k++
        else
            lines = this._lines
            for lineID of lines
                div = $ lines[lineID].line$[0]
                div.attr('toDisplay', '')

    #### -------------------------------------------------------------------
    # (de)activates class auto-display at the beginning of lines
    $("#addClass2LineBtn").on "click", () ->
        addClassToLines()
        if editor_doAddClasseToLines
            $("#addClass2LineBtn").html "Show Class on Lines"
            editor_doAddClasseToLines = false
            editorBody$.off 'keyup' , addClassToLines
            removeClassFromLines()
        else
            $("#addClass2LineBtn").html "Hide Class on Lines"
            editor_doAddClasseToLines = true
            editorBody$.on 'keyup' , addClassToLines

    #### -------------------------------------------------------------------
    # auto check of the syntax after a paste
    editorBody$.on "paste", () ->
        window.setTimeout( ()->
            res = checker.checkLines(editorCtrler)
            date = new Date()
            st = date.getHours()+":"+date.getMinutes()+":"+date.getSeconds()+" - "
            if res
                $("#resultText").val(st+"Syntax test success")
            else
                $("#resultText").val(st+"Syntax test FAILLURE : cf logs")
        , 400)
        
    # default behaviour regarding the class at the beginning of the line :
    # comment or uncomment depending default expected behaviour
    # addClassToLines()
    # $("#addClass2LineBtn").html "Hide Class on Lines"
    # editorBody$.on 'keyup', addClassToLines
    # editor_doAddClasseToLines = true
    
    $("#logEditorCtrlerBtn").on "click", () ->
        console.log editorCtrler


    # automatic summary
    # this.editorBody$.on 'mouseup', () =>
    #     this.buildSummary()
    # this.editorBody$.on 'keyup', () =>
    #     this.buildSummary()



###****************************************************
 * 3 - creation of the editor
###
editor = new CNeditor( document.querySelector('#editorIframe'), cb )