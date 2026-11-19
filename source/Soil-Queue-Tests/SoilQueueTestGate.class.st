"
A gate that a test opens and shuts from outside: it lets out as many as it is told to, says
when it opens as it is told to, and counts the entries that left through it (#taken).
"
Class {
	#name : #SoilQueueTestGate,
	#superclass : #SoilQueueGate,
	#instVars : [
		'allowance',
		'opensAt',
		'taken'
	],
	#category : #'Soil-Queue-Tests'
}

{ #category : #accessing }
SoilQueueTestGate >> allowance: anInteger [

	allowance := anInteger
]

{ #category : #accessing }
SoilQueueTestGate >> allowanceAt: aDateAndTime [

	^ allowance
]

{ #category : #initialization }
SoilQueueTestGate >> initialize [

	super initialize.
	allowance := 0.
	taken := 0
]

{ #category : #accessing }
SoilQueueTestGate >> nextOpenAfter: aDateAndTime [

	^ opensAt
]

{ #category : #accessing }
SoilQueueTestGate >> opensAt: aDateAndTime [
	"when it says it can open again; nil is 'cannot say'"

	opensAt := aDateAndTime
]

{ #category : #accessing }
SoilQueueTestGate >> take [

	taken := taken + 1
]

{ #category : #accessing }
SoilQueueTestGate >> taken [
	"how many entries left through me"

	^ taken
]
