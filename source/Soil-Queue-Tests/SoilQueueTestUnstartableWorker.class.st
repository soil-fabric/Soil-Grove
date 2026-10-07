"
A worker that cannot be started, the way a fork that fails cannot: it is there, it takes
no entry, and its #run never begins.
"
Class {
	#name : #SoilQueueTestUnstartableWorker,
	#superclass : #SoilQueueWorker,
	#category : #'Soil-Queue-Tests'
}

{ #category : #running }
SoilQueueTestUnstartableWorker >> start [

	self error: 'the process could not be started'
]
