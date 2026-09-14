"
The first resumption semantics: work that comes in steps and picks up where it left off.

I do one step per work unit -- the effect on my target first, then the note that it
happened, and the note is my #progress. That order is the rule for external effects: a
crash between the two costs one repeated effect, the other order loses one altogether,
and the queue promises at least once rather than exactly once.

My target counts the steps it owes in the size of its effects; how many it owes comes
from #stepsOwed.
"
Class {
	#name : #SoilQueueTestContinuingEntry,
	#superclass : #SoilQueueEntry,
	#instVars : [
		'stepsOwed'
	],
	#category : #'Soil-Queue-Tests'
}

{ #category : #'instance creation' }
SoilQueueTestContinuingEntry class >> on: aTarget steps: anInteger [

	^ (self on: aTarget)
		stepsOwed: anInteger;
		yourself
]

{ #category : #accessing }
SoilQueueTestContinuingEntry class >> resumption [

	^ #continuing
]

{ #category : #initialization }
SoilQueueTestContinuingEntry >> initialize [

	super initialize.
	stepsOwed := 1.
	self progress: 0
]

{ #category : #working }
SoilQueueTestContinuingEntry >> performIn: aTransaction [

	| step |
	step := self progress + 1.
	self target addEffect: step.
	self progress: step.
	^ step < stepsOwed
		ifTrue: [ #more ]
		ifFalse: [ #finished ]
]

{ #category : #accessing }
SoilQueueTestContinuingEntry >> stepsOwed [

	^ stepsOwed
]

{ #category : #accessing }
SoilQueueTestContinuingEntry >> stepsOwed: anInteger [

	stepsOwed := anInteger
]
