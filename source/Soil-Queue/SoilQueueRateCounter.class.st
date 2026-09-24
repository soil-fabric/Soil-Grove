"
What has gone out lately: the times at which a queue handed out entries, kept for as long
as they still count against its rate. That is any period of the given length, not the
minute on the clock -- an entry handed out half a minute ago still counts half a minute
from now.

I live in memory and only there. A counter in the store would be a structure every worker
writes to, which under MVCC is where write conflicts come from; and a restart that forgets
what went out lately lets at most one period's worth out early.

The limit and the period are not mine. They belong to the description and are passed in
with every question, so a changed setting holds from the next question on. That also keeps
me small enough that a queue could hold several of me, one per key of its entries, without
anything else changing.

Asked under the queue's mutex, like everything that competing workers meet at.
"
Class {
	#name : #SoilQueueRateCounter,
	#superclass : #Object,
	#instVars : [
		'issued'
	],
	#category : #'Soil-Queue'
}

{ #category : #accessing }
SoilQueueRateCounter >> allowanceAt: aDateAndTime limit: anInteger period: aDuration [
	"how many more may go out at aDateAndTime"

	self forgetBefore: aDateAndTime - aDuration.
	^ (anInteger - issued size) max: 0
]

{ #category : #accessing }
SoilQueueRateCounter >> forgetBefore: aDateAndTime [
	"what went out at or before aDateAndTime no longer counts"

	[ issued notEmpty and: [ issued first <= aDateAndTime ] ]
		whileTrue: [ issued removeFirst ]
]

{ #category : #accessing }
SoilQueueRateCounter >> freeAt: aDateAndTime limit: anInteger period: aDuration [
	"from when the next one may go out: aDateAndTime itself when there is room, otherwise
	the moment the oldest that still counts stops counting"

	self forgetBefore: aDateAndTime - aDuration.
	issued size < anInteger ifTrue: [ ^ aDateAndTime ].
	^ issued first + aDuration
]

{ #category : #initialization }
SoilQueueRateCounter >> initialize [

	super initialize.
	issued := OrderedCollection new
]

{ #category : #accessing }
SoilQueueRateCounter >> noteIssueAt: aDateAndTime [

	issued addLast: aDateAndTime
]
