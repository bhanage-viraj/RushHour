//
//  DistractionViewModel.swift
//  lucky7
//
//  Created by Andrian on 31/05/26.
//
import Foundation
import Combine
import SwiftData

@MainActor
class DistractionStat: ObservableObject {
    @Published var distractions: [Distraction] = []
    @Published var totalDistractionDuration: TimeInterval = 0.0
    
    var distractionCount: Int {
        distractions.count
    }

    func fetchDistractions(for session: Session, context: ModelContext) {
        fetchDistractions(
            for: session.id,
            context: context,
            sessionStart: session.startTime,
            sessionEnd: session.endTime ?? Date()
        )
    }
    
    func fetchDistractions(
        for sessionId: UUID,
        context: ModelContext,
        sessionStart: Date? = nil,
        sessionEnd: Date? = nil
    ) {
        do {
            let descriptor = FetchDescriptor<Distraction>(
                predicate: #Predicate { $0.sessionId == sessionId},
                sortBy: [SortDescriptor(\Distraction.startTime)]
            )
            
            let fetchedDistraction = try context.fetch(descriptor)
            self.distractions = fetchedDistraction

            if let sessionStart, let sessionEnd {
                self.totalDistractionDuration = distractions.reduce(0.0) {
                    $0 + $1.durationClamped(toStart: sessionStart, end: sessionEnd)
                }
            } else {
                self.totalDistractionDuration = distractions.reduce(0.0) { $0 + $1.distractionDuration }
            }

        } catch {
            print("Error fetching distractions count: \(error)")
        }
    }
}
