"
The cadence of a queue's dispatcher: a step when work was handed in, and a step when the
next entry falls due -- whichever comes first.

The due time is the queue's #wakeAt, a value in memory. I never read the ordering myself:
waiting happens between two steps, and a transaction opened here would be open at the
moment an embedder decides the database is quiet enough to close. The steps read, and
they leave behind what they found.

The sleep is a timed wait on the resident's work signal, so everything that signals it
ends it early: new work, a stop, a worker that found an earlier due time. After each
wake-up I look again rather than step, because a signal only says that something
happened -- a stop wants no step, and an earlier due time wants a shorter sleep.
"
Class {
	#name : #SoilQueueRunStrategy,
	#superclass : #SoilResidentRunStrategy,
	#category : #'Soil-Queue'
}

{ #category : #running }
SoilQueueRunStrategy >> awaitDue [

	[ self isDue or: [ resident shouldStop ] ] whileFalse: [
		resident timeUntilWake
			ifNil: [ resident waitForWork ]
			ifNotNil: [ :aDuration | resident waitForWorkUpTo: aDuration ] ]
]

{ #category : #testing }
SoilQueueRunStrategy >> isDue [
	"whether the next step should happen now: work was handed in, or the time the next
	entry falls due has come"

	^ resident hasPendingWork or: [
		resident timeUntilWake
			ifNil: [ false ]
			ifNotNil: [ :aDuration | aDuration <= 0 seconds ] ]
]
