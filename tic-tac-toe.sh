#!/bin/bash

# arg1, arg2 - ports for connection
main(){
    trap "finish; exit" SIGHUP SIGINT SIGTERM

    PORTRecieve=$1
    PORTSend=$2

    crossesChar="X"
    noughtsChar="O"
    observerChar="*"
    emptyChar="."

    local currentTurnNumber=1
    local currentTurn
    local PlayerStatus
    local boardSymbol
    local gameResult

    declare -a turnDelegate
    turnDelegate[2]=thisPlayerTurn
    turnDelegate[1]=opponenTurn

    declare -a board
    initBoard

    setConnection PlayerStatus

    if [[ $PlayerStatus = crosses ]] ; then
        boardSymbol=$crossesChar
        currentTurn="${turnDelegate[2]}"
    elif [[ $PlayerStatus = noughts ]]; then
        boardSymbol=$noughtsChar
        currentTurn="${turnDelegate[1]}"
        turnDelegate[1]="${turnDelegate[2]}"
        turnDelegate[2]="$currentTurn"
    elif [[ $PlayerStatus = observer ]]; then
        boardSymbol=$observerChar
        currentTurn=observerTurn
        turnDelegate[1]="$currentTurn"
        turnDelegate[2]="$currentTurn"
    else
        echo "ERROR: Can't find match for player status."
        exit -1
    fi

    render
    while [[ ! $gameResult ]]; do
        $currentTurn
        ((currentTurnNumber+=1))
        render
        checkWinner
        currentTurn="${turnDelegate[$currentTurnNumber%2+1]}"
    done

    finish
}

# arg1 - isSilent
sendTurn(){
    if [[ ! $1 ]]; then echo "Sending..."; fi
    # sleep 0.01 -- time for another process to lock port
    while echo "${board[*]}" | nc localhost $PORTSend 2>/dev/null 1>/dev/null ; do if [[ ! $1 ]]; then echo "+1 sended"; fi; sleep 0.01; done
}

thisPlayerTurn(){
    local row
    local column
    echo "Your turn ($PlayerStatus), input row and column: "
    while [[ true ]]; do
        read row column
        if [[ $row -lt 1 ]] || [[ $row -gt 3 ]] || [[ $column -lt 1 ]] || [[ $column -gt 3 ]]; then
            echo "Invalid input. Format: \"Number Number\", Number can be only 1,2 or 3."
            echo "Repeat input, row column: "
            continue
        fi
        if [[ $(getBoardCell row column) != $emptyChar ]]; then
            echo "Play on empty cell!"
            echo "Repeat input, row column: "
            continue
        fi
        break
    done

    setBoardCell $boardSymbol row column

    sendTurn true
}

opponenTurn(){
    local reply
    echo "Waiting of another player..."
    until reply=$(echo "${board[*]}" | nc -l $PORTRecieve 2>/dev/null); do :; done
    declare -a reply_values
    reply_values=($reply)

    while [[ ${reply_values[0]} = WAITING ]] ; do
        sendTurn true
        until reply=$(echo "${board[*]}" | nc -l $PORTRecieve 2>/dev/null);do :; done
        reply_values=($reply)
    done

    if [[ ${reply_values[0]} = FINISH ]]; then
        gameResult=${reply_values[*]:1}
        finish
        exit 0
    fi

    board=($reply)
}

observerTurn(){
    local tempPort=$PORTSend
    PORTSend=$PORTRecieve
    PORTRecieve=$tempPort
    opponenTurn
}

checkWinner(){
    local isDraw=true
    for (( i = 1; i <= 3; i++ )); do
        for (( j = 1; j <= 3; j++ )); do
            if [[ $(getBoardCell i j) = $emptyChar ]]; then
                isDraw= #false
                break
            fi
        done
    done

    if [[ $isDraw ]]; then
        gameResult="Draw"
    fi

    for (( i = 1; i <= 3; i++ )); do
        if [[ $(getBoardCell $i 1) != $emptyChar &&\
         $(getBoardCell $i 1) = $(getBoardCell $i 2) &&\
          $(getBoardCell $i 2) = $(getBoardCell $i 3) ]]; then
            gameResult=$(getBoardCell $i 1)
        fi
        if [[ $(getBoardCell 1 $i) != $emptyChar &&\
         $(getBoardCell 1 $i) = $(getBoardCell 2 $i) &&\
          $(getBoardCell 2 $i) = $(getBoardCell 3 $i) ]]; then
            gameResult=$(getBoardCell 1 $i)
        fi
    done
    if [[ $(getBoardCell 1 1) != $emptyChar &&\
     $(getBoardCell 1 1) = $(getBoardCell 2 2) &&\
      $(getBoardCell 2 2) = $(getBoardCell 3 3) ]]; then
        gameResult=$(getBoardCell 1 1)
    elif [[ $(getBoardCell 1 3) != $emptyChar &&\
     $(getBoardCell 1 3) = $(getBoardCell 2 2) &&\
      $(getBoardCell 2 2) = $(getBoardCell 3 1) ]]; then
        gameResult=$(getBoardCell 1 3)
    fi
}

#arg1 - variable name to store result
setConnection(){
    local _result=$1
    local reply
    local meFirst

    myRandom=$RANDOM

    echo "Waiting for response..."

    reply=$(echo "WAITING "$myRandom | nc localhost $PORTSend)
    if [[ $reply ]] ; then
        meFirst= #false
    else
        reply=$(echo "WAITING "$myRandom | nc localhost $PORTRecieve)
        if [[ $reply ]]; then
            meFirst= #false
            local tempPort=$PORTSend
            PORTSend=$PORTRecieve
            PORTRecieve=$tempPort
        else
            meFirst=true
            reply=$(echo "WAITING "$myRandom | nc -l $PORTRecieve 2>/dev/null)
        fi
    fi

    local reply_values=($reply)
    local status=${reply_values[0]}

    if [[ ${status[0]} = WAITING ]] ; then
        local theirRandom=${reply_values[1]}
        echo "My random number: $myRandom, their random number: $theirRandom"
        if [[ $myRandom -gt $theirRandom ]] ; then
            eval $_result=crosses
        elif [[ $myRandom -eq $theirRandom ]] ; then
            if meFirst ; then
                eval $_result=crosses
            else
                eval $_result=noughts
            fi
        else
            eval $_result=noughts
        fi
    elif [[ ${status[0]} = FINISH ]]; then
        gameResult=${reply_values[1]:1}
        finish
        exit 0
    else
        eval $_result=observer
        board=($reply)
    fi
}

finish(){
    local message
    if [[ $gameResult = $crossesChar ]]; then
        message="Crosses win!"
    elif [[ $gameResult = $noughtsChar ]]; then
        message="Noughts win!"
    elif [[ $gameResult = "Draw" ]]; then
        message="Draw!"
    else
        message="Game finished."
    fi

    echo $message

    message="FINISH $gameResult"

    if [[ $currentTurn = "thisPlayerTurn" ]]; then
        if [[ $gameResult = "Draw" || $gameResult = $noughtsChar || $gameResult = $crossesChar ]]; then
            while echo "${board[*]}" | nc localhost $PORTSend 2>/dev/null 1>/dev/null; do sleep 0.01; done
            while echo "${board[*]}" | nc localhost $PORTRecieve 2>/dev/null 1>/dev/null; do sleep 0.01; done
        else
            while echo "$message" | nc localhost $PORTSend 2>/dev/null 1>/dev/null; do sleep 0.01; done
            while echo "$message" | nc localhost $PORTRecieve 2>/dev/null 1>dev/null; do sleep 0.01; done
        fi
    fi
}

render(){
    clear
    for (( i = 1; i <= 3; i++ )); do
        echo "$(getBoardCell $i 1)|$(getBoardCell $i 2)|$(getBoardCell $i 3)"
    done
}

initBoard(){
    for (( i = 1; i <= 3; i++ )); do
        for (( j = 1; j <= 3; j++ )); do
            setBoardCell $emptyChar $i $j
        done
    done
}

# arg1 - value, arg2 - row, arg3 - column, row and column are one-indexed
setBoardCell(){
    board[$((($2-1)*3 + ($3-1)))]="$1"
}

# arg1 - row, arg2 - column, row and column are one-indexed
getBoardCell(){
    echo ${board[($1-1)*3+($2-1)]}
}

main 6666 6667
