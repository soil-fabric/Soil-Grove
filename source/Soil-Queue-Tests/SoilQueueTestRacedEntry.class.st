"
An entry whose work unit is raced every time: before its transaction commits, another one
writes the same target and commits first. The work unit then meets a write conflict at its
commit, inside the lock the commit holds on the database -- not signalled by hand, as
SoilQueueTestConflictingEntry signals it, but the way a conflict arises. It never goes
through.

The other transaction finds the target under #target in the root, where the tests put it.
"
Class {
	#name : #SoilQueueTestRacedEntry,
	#superclass : #SoilQueueEntry,
	#category : #'Soil-Queue-Tests'
}

{ #category : #working }
SoilQueueTestRacedEntry >> performIn: aTransaction [

	self target addEffect: #attempt.
	self raceFor: aTransaction.
	^ #finished
]

{ #category : #working }
SoilQueueTestRacedEntry >> raceFor: aTransaction [
	"another transaction writes my target and commits, before aTransaction does"

	| other |
	other := aTransaction soil newTransaction.
	[ (other root at: #target) addEffect: #meanwhile.
	  other commit ]
		ensure: [ other isAborted ifFalse: [ other abort ] ]
]

{ #category : #working }
SoilQueueTestRacedEntry >> resumeAfterAbortIn: aTransaction [
	"repeating: what I do to my target lies in the transaction of the attempt, and an attempt
	that met the conflict wrote nothing"
]
