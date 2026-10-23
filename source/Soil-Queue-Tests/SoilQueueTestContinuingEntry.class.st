"
The first resumption semantics: work that comes in steps and picks up where it left off.

I do one step per work unit -- the effect on my target first, then the note that it
happened, and the note is my #progress. That order is the rule for external effects: a
crash between the two costs one repeated effect, the other order loses one altogether,
and the queue promises at least once rather than exactly once. After the note I say that
the step went through (#noteStepDone), which ends a row of retries; the queue cannot tell
that from my answer.

My target counts the steps it owes in the size of its effects; how many it owes comes
from #stepsOwed.
"
Class {
	#name : #SoilQueueTestContinuingEntry,
	#superclass : #SoilQueueEntry,
	#instVars : [
		'stepsOwed',
		'progress'
	],
	#category : #'Soil-Queue-Tests'
}

{ #category : #'instance creation' }
SoilQueueTestContinuingEntry class >> on: aTarget steps: anInteger [

	^ (self on: aTarget)
		stepsOwed: anInteger;
		yourself
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
	self noteStepDone.
	^ step < stepsOwed
		ifTrue: [ #more ]
		ifFalse: [ #finished ]
]

{ #category : #accessing }
SoilQueueTestContinuingEntry >> progress [
	"how many steps I have done, 0 before the first. A field of mine, because my target
	has no state machine that would know"

	^ progress
]

{ #category : #accessing }
SoilQueueTestContinuingEntry >> progress: anInteger [
	"set after the effect it stands for -- see the class comment of SoilQueueEntry"

	progress := anInteger
]

{ #category : #working }
SoilQueueTestContinuingEntry >> resumeAfterAbortIn: aTransaction [
	"continuing: my progress was committed with each step, so I pick up where it says.
	Nothing to put right"
]

{ #category : #accessing }
SoilQueueTestContinuingEntry >> stepsOwed [

	^ stepsOwed
]

{ #category : #accessing }
SoilQueueTestContinuingEntry >> stepsOwed: anInteger [

	stepsOwed := anInteger
]
