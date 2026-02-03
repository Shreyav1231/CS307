import SwiftUI
import PDFKit
import UIKit

struct PDFKitView: UIViewRepresentable {
    let pdfURL: URL
    @Binding var selectedAnchor: SelectedAnchor?
    @Binding var lastCapturedAnchor: SelectedAnchor?
    let pageMarkers: [Int: [MarkerPoint]]  // Persistent markers per page

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.usePageViewController(false)
        
        let doc = PDFDocument(url: pdfURL)
        pdfView.document = doc
        
        context.coordinator.pdfView = pdfView
        context.coordinator.currentURL = pdfURL
        
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        pdfView.addGestureRecognizer(tap)
        
        context.coordinator.redraw(
            selected: selectedAnchor,
            lastCaptured: lastCapturedAnchor,
            pageMarkers: pageMarkers
        )

        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        let coordinator = context.coordinator
        
        if coordinator.currentURL != pdfURL {
            coordinator.currentURL = pdfURL
            let doc = PDFDocument(url: pdfURL)
            pdfView.document = doc
        }
        
        coordinator.onTap = { anchor in
            self.selectedAnchor = anchor
        }
        
        coordinator.redraw(
            selected: selectedAnchor,
            lastCaptured: lastCapturedAnchor,
            pageMarkers: pageMarkers
        )
    }

    final class Coordinator: NSObject {
        weak var pdfView: PDFView?
        var currentURL: URL?
        var onTap: ((SelectedAnchor) -> Void)?

        @objc func handleTap(_ gr: UITapGestureRecognizer) {
            guard let pdfView = pdfView,
                  let doc = pdfView.document else { return }

            let viewPoint = gr.location(in: pdfView)
            guard let page = pdfView.page(for: viewPoint, nearest: true) else { return }

            let pagePoint = pdfView.convert(viewPoint, to: page)
            let pageIndex = doc.index(for: page)

            let anchor = SelectedAnchor(
                pageIndex: pageIndex,
                xPDF: Double(pagePoint.x),
                yPDF: Double(pagePoint.y)
            )
            
            onTap?(anchor)
        }

        func redraw(selected: SelectedAnchor?, lastCaptured: SelectedAnchor?, pageMarkers: [Int: [MarkerPoint]]) {
            guard let pdfView = pdfView,
                  let doc = pdfView.document else { return }

            // Remove all annotations from all pages
            for i in 0..<doc.pageCount {
                guard let page = doc.page(at: i) else { continue }
                for ann in page.annotations {
                    page.removeAnnotation(ann)
                }
            }

            let r: CGFloat = 10

            // Blue circles for persistent markers (from pageMarkers)
            for (pageIndex, markers) in pageMarkers {
                guard pageIndex >= 0, pageIndex < doc.pageCount,
                      let page = doc.page(at: pageIndex) else { continue }
                
                for marker in markers {
                    // Alpha increases with capture count
                    let alpha = min(0.12 + 0.06 * Double(marker.captureCount - 1), 0.50)
                    let rect = CGRect(x: CGFloat(marker.x) - r, y: CGFloat(marker.y) - r, width: r * 2, height: r * 2)

                    let ann = PDFAnnotation(bounds: rect, forType: .circle, withProperties: nil)
                    ann.border = PDFBorder()
                    ann.border?.lineWidth = 0
                    let fill = UIColor.systemBlue.withAlphaComponent(CGFloat(alpha))
                    ann.interiorColor = fill
                    ann.color = fill
                    page.addAnnotation(ann)
                    
                    // Add count label if more than 1
                    if marker.captureCount > 1 {
                        let labelRect = CGRect(x: CGFloat(marker.x) - 6, y: CGFloat(marker.y) - 6, width: 12, height: 12)
                        let label = PDFAnnotation(bounds: labelRect, forType: .freeText, withProperties: nil)
                        label.contents = "\(marker.captureCount)"
                        label.font = UIFont.boldSystemFont(ofSize: 8)
                        label.fontColor = UIColor.white
                        label.color = UIColor.clear
                        page.addAnnotation(label)
                    }
                }
            }

            // Orange circle for last captured point
            if let lc = lastCaptured,
               lc.pageIndex >= 0,
               lc.pageIndex < doc.pageCount,
               let page = doc.page(at: lc.pageIndex) {

                let rect = CGRect(x: CGFloat(lc.xPDF) - r, y: CGFloat(lc.yPDF) - r, width: r * 2, height: r * 2)
                let ann = PDFAnnotation(bounds: rect, forType: .circle, withProperties: nil)
                ann.border = PDFBorder()
                ann.border?.lineWidth = 3
                ann.color = UIColor.systemOrange
                ann.interiorColor = UIColor.clear
                page.addAnnotation(ann)
            }

            // Red circle for current selection (if different from lastCaptured)
            if let sel = selected,
               sel != lastCaptured,
               sel.pageIndex >= 0,
               sel.pageIndex < doc.pageCount,
               let page = doc.page(at: sel.pageIndex) {

                let rect = CGRect(x: CGFloat(sel.xPDF) - r, y: CGFloat(sel.yPDF) - r, width: r * 2, height: r * 2)
                let ann = PDFAnnotation(bounds: rect, forType: .circle, withProperties: nil)
                ann.border = PDFBorder()
                ann.border?.lineWidth = 3
                ann.color = UIColor.systemRed
                ann.interiorColor = UIColor.clear
                page.addAnnotation(ann)
            }
            
            pdfView.setNeedsDisplay()
            pdfView.setNeedsLayout()
            pdfView.layoutIfNeeded()
            
            if let currentPage = pdfView.currentPage {
                pdfView.go(to: currentPage)
            }
        }
    }
}
