debugging = true
log = (mesg) ->  console.log mesg if debugging
if not deepcopy?
    deepcopy = (src) -> $.extend(true, {},src)

class window.GameManager
    constructor: (@environment) ->
        @config = @environment.description
        @loadDefaultsIfUndefined()

        @editorDiv = 'codeEditor'
        @visualDiv = 'gameVisual'
        @setUpGame()

    setUpGame: ->
        ###
            Sets up everything for the game to run.
        ###
        @gameDiv = jQuery @environment.gamediv
        editdiv = document.createElement("div")
        vis = document.createElement("div")

        $(editdiv).attr({'id':@editorDiv,'class':'code_editor'})
        $(editdiv).css({width:'30%',height:'90%','position':'absolute','top':'5%','left':'5%'})

        $(vis).attr({'id':@visualDiv,'class':'game_visual'})
        $(vis).css({width:'40%',height:'90%','position':'absolute','top':'5%','right':'5%'})

        @gameDiv.append(editdiv)
        $(editdiv).append '<button id="compileAndRun">Go</button>'
        $(editdiv).append '<button id="resetState">Reset</button>'
        @gameDiv.append(vis)

        @codeEditor = new EditorManager @editorDiv, @config.editor, @config.code
        @interpreter = new CodeInterpreter @config.editor.commands

        @environment.visualMaster.container.id = @visualDiv
        @visual = new GameVisual @environment.visualMaster, @environment.frameRate
        @addEventListeners()
        return

    startGame: ->
        @config.visual.characters.protagonist.x = @config.game.startpos[0] - 1
        @config.visual.characters.protagonist.y = @config.game.startpos[1] - 1
        @visual.startGame @config.visual
        @gameState = new MapGameState this, @visual, @config.visual.characters
        @commandMap = new MapGameCommands @gameState
        return

    gameWon: (score, stars) ->
        log "Game Won: #{@environment.key}"
        player = @environment.player
        if player.games[@environment.key]?
            if @player.games[@environment.key].hiscore? > score
                score = @player.games[@environment.key].hiscore

            if @player.games[@environment.key].stars? > stars
                stars = @player.games[@environment.key].stars

        @environment.codeland.storeGameCompletionData @environment.key, {
            hiscore : score,
            stars : stars,
            passed : true
        }
        @finishGame()
        return

    finishGame: ->
        @codeEditor = null
        @interpreter = null
        @visual = null
        @gameDiv.empty()
        return

    addEventListeners: ->
        jQuery('#compileAndRun').click @runStudentCode
        jQuery('#resetState').click @reset
        return

    reset: =>
        @codeEditor.resetEditor()
        @gameState = new MapGameState this, @visual, @config.visual.characters
        @commandMap = new MapGameCommands @gameState
        @visual.startGame @config.visual
        return

    runStudentCode: =>
        @interpreter.scanText @codeEditor.getStudentCode()
        @interpreter.executeCommands @commandMap
        return

    loadDefaultsIfUndefined: ->
        if not @config.editor?
            @config.editor = {}
        if not @config.code?
            @config.code = {}

        if not @config.editor.buttons?
            @config.editor.buttons = ['switchUp', 'switchDown',
                'deleteLine', 'insertButtons']
        if not @config.editor.commands?
            @config.editor.commands = {
                    go: {
                        inputs: 1,
                        maxUses: 3
                    },
                    turnRight: {
                        inputs: 0,
                        maxUses: 2
                    },
                    turn: {
                        inputs: 2,
                        maxUses: 3
                    }
                }

        if not @config.code.prefix?
            @config.code.prefix = """
                public class Student {
                public static void main(String[] args) {\n
                """
        if not @config.code.initial?
            @config.code.initial = """
                go(15);
                turnRight();
                turn(__, __);
                go(2);
                """
        if not @config.code.postfix?
            @config.code.postfix = '}\n}'

        if not @environment.visualMaster?
            @environment.visualMaster = {}

        if not @environment.visualMaster.container?
            @environment.visualMaster.container = {
                width: 360,
                height: 360
            }

        if not @environment.visualMaster.preLoading?
            @environment.visualMaster.preLoading = {
                protagonist: [
                    "img/wmn1_bk1.gif","img/wmn1_bk2.gif",
                    "img/wmn1_rt1.gif","img/wmn1_rt2.gif",
                    "img/wmn1_fr1.gif","img/wmn1_fr2.gif",
                    "img/wmn1_lf1.gif","img/wmn1_lf2.gif"
                ]
            }
        return

class MapGameState
    #<--DIRECTIONS-->
    #       ^
    #       0
    #   < 3 4 1 >
    #       2
    #       v
    constructor: (@gameManager, @gameVisual, characterLoadconfig) ->
        # @config ?= { x: 4, y: 4, direction: 0, maxX:9, maxY:9, traps: [[2,4],[9,9]], targets: [[5,5]], targetCount : 0}
        @config = deepcopy @gameManager.config.game
        @score = 0
        @stars = 0
        @protagonist = {
            x: @config.startpos[0],
            y: @config.startpos[1],
            dir: if @config.direction? then @config.direction else 0,
            index: 0
        }
        @target = {
            x: @config.targetpos[0]
            y: @config.targetpos[1]
        }
        @gameVisual.charFace @protagonist.index, @protagonist.dir
        return

    gameWon: ->
        @gameManager.gameWon @score, @stars
        return

    checkEvent: (playerX, playerY) ->
        log "Checking: X: #{playerX}, Y: #{playerY}"
        canMove = true
        if playerX < 1 or playerX > @gameManager.config.visual.gridX + 1\
          or playerY < (-1 * @gameManager.config.visual.gridY + 1) or playerY > 1
            # Player is out of bounds of grid.
            canMove = false
            log "Out of bounds!"
        log "canMove: #{canMove}"
        return canMove

    move: (steps) ->
        # Bits are more fun that lookup tables or a switch
        # sign is positive 1 for North00, East01, and -1 for South10, West11
        [sign, isEastOrWest] = [1  - (@protagonist.dir & 2), @protagonist.dir & 1]
        if isEastOrWest
            newx = @protagonist.x + sign
            newy = @protagonist.y
        unless isEastOrWest
            newx = @protagonist.x
            newy = @protagonist.y + sign

        updatePlayerPosition = @checkEvent(newx, newy)
        if updatePlayerPosition
            @protagonist.x = newx
            @protagonist.y = newy
            @gameVisual.gridMove @protagonist.index, steps

        return

    turnRight: ->
        @turn ((@protagonist.dir + 1) % 4)
        return

    turnLeft: ->
        @turn ((@protagonist.dir + 3) % 4)
        return

    turn: (dir) ->
        @protagonist.dir = dir
        @gameVisual.charFace @protagonist.index, @protagonist.dir
        return

class MapGameCommands
    constructor: (@gameState) ->
        return

    go: (steps) =>
        steps = 1 if steps is undefined
        # log "Go #{steps} steps."
        @gameState.move steps

    turn: (dir) =>
        # log "turn '#{dir}'"
        return if dir is undefined
        d = $.inArray(dir, ['N','E','S','W'])
        if d >= 0
            @gameState.turn d
        else
            d = $.inArray(dir, ['North','East','South','West'])
            if d >= 0
                @gameState.turn d
            else
                @gameState.turn (4 + dir % 4) % 4
        return

    turnRight: =>
        # log "turnRight"
        @gameState.turnRight()
        return

    turnLeft: =>
        # log "turnLeft"
        @gameState.turnLeft()
        return

    turnAndGo: (direction, steps) =>
        # log "turnAndGo #{direction} #{steps}"
        @turn direction
        @go steps
        return

    goNorth: (steps) => @turnAndGo 0, steps
    goEast:  (steps) => @turnAndGo 1, steps
    goWest:  (steps) => @turnAndGo 2, steps
    goSouth: (steps) => @turnAndGo 3, steps

    # used in sequence4
    mysteryA: => @goEast 4
    mysteryB: => @goSouth 1
    mysteryC: => @goWest 2
