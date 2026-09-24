"
An entry that goes on, but not right away: its first work unit moves its own due time
later and answers #more, the second one finishes. That is the follow-up of §5.2 -- a
step that says 'again, at such a time' -- and it is the case in which the queue has to
move the key, because the key is what sorts by the due time.

The later time is taken from my own due time rather than from a clock. An entry has no
clock of its own, and the test decides what 'now' is through the queue's.
"
Class {
	#name : #SoilQueueTestPostponingEntry,
	#superclass : #SoilQueueTestEntry,
	#instVars : [
		'delay'
	],
	#category : #'Soil-Queue-Tests'
}

{ #category : #'instance creation' }
SoilQueueTestPostponingEntry class >> on: aTarget postponedBy: aDuration [

	^ (self on: aTarget)
		setDelay: aDuration;
		yourself
]

{ #category : #working }
SoilQueueTestPostponingEntry >> performIn: aTransaction [

	super performIn: aTransaction.
	self runCount = 1 ifFalse: [ ^ #finished ].
	self eligibleAt: self eligibleAt + delay.
	^ #more
]

{ #category : #initialization }
SoilQueueTestPostponingEntry >> setDelay: aDuration [

	delay := aDuration
]
