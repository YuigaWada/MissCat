//
//  FileContainer.swift
//  MissCat
//
//  Created by Yuiga Wada on 2020/03/23.
//  Copyright © 2020 Yuiga Wada. All rights reserved.
//

import Agrume
import MisskeyKit
import RxCocoa
import RxDataSources
import RxSwift
import UIKit

typealias FileDataSource = RxCollectionViewSectionedReloadDataSource<FileContainer.Section>
class FileContainer: UICollectionView, UICollectionViewDelegate, ComponentType {
    typealias Transformed = FileContainer
    struct Arg {
        let files: [File]
        let noteId: String
        let fileVisible: Bool
        let delegate: NoteCellDelegate?
    }
    
    private lazy var viewModel = FileContainerViewModel(disposeBag: disposeBag)
    
    private var noteCellDelegate: NoteCellDelegate?
    private let disposeBag = DisposeBag()
    
    // MARK: LifeCycle
    
    override init(frame: CGRect, collectionViewLayout layout: UICollectionViewLayout) {
        super.init(frame: frame, collectionViewLayout: MosaicLayout())
        binding()
        isScrollEnabled = false
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        binding()
        isScrollEnabled = false
    }
    
    // MARK: Publics
    
    func transform(with arg: Arg) -> FileContainer {
        initialize()
        
        noteCellDelegate = arg.delegate
        collectionViewLayout = MosaicLayout()
        DispatchQueue.global().async {
            self.viewModel.setFileModel(with: arg)
        }
        return self
    }
    
    func initialize() {
        viewModel.fileModel = []
    }
    
    // MARK: Setup
    
    private func binding() {
        let fileDataSources = setupDataSource()
        let files = viewModel.output.files.asDriver(onErrorDriveWith: Driver.empty())
        
        files.drive(rx.items(dataSource: fileDataSources)).disposed(by: disposeBag)
    }
    
    private func setupDataSource() -> FileDataSource {
        register(UINib(nibName: "FileContainerCell", bundle: nil), forCellWithReuseIdentifier: "FileContainerCell")
        rx.setDelegate(self).disposed(by: disposeBag)
        
        let dataSource = FileDataSource(
            configureCell: { dataSource, collectionView, indexPath, _ in
                self.setupCell(dataSource, collectionView, indexPath)
            }
        )
        
        return dataSource
    }
    
    private func setupCell(_ dataSource: CollectionViewSectionedDataSource<FileContainer.Section>, _ collectionView: UICollectionView, _ indexPath: IndexPath) -> UICollectionViewCell {
        let index = indexPath.row
        let fileModel = viewModel.fileModel
        
        guard let cell = dequeueReusableCell(withReuseIdentifier: "FileContainerCell", for: indexPath) as? FileContainerCell else { fatalError("Internal Error.") }
        
        if index < fileModel.count {
            let item = fileModel[index]
            cell.transform(with: item, and: noteCellDelegate)
        }
        
        return cell
    }
    
    // MARK: Delegate
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let index = indexPath.row
        let fileModel = viewModel.fileModel
        guard index < fileModel.count else { return }
        let item = fileModel[index]
        
        if item.isVideo {
            noteCellDelegate?.playVideo(url: item.originalUrl)
        } else {
            showImage(url: item.originalUrl)
        }
    }
    
    private func showImage(url: String) {
        guard let url = URL(string: url), let delegate = noteCellDelegate as? UIViewController else { return }
        
        let agrume = Agrume(url: url)
        agrume.show(from: delegate) // 画像を表示
    }
}

extension FileContainer {
    struct Model: IdentifiableType, Equatable {
        typealias Identity = String
        
        var identity: String = UUID().uuidString
        
        let thumbnailUrl: String
        let originalUrl: String
        let isVideo: Bool
        let isSensitive: Bool
    }
    
    struct Section {
        var items: [Model]
    }
}

extension FileContainer.Section: AnimatableSectionModelType {
    typealias Item = FileContainer.Model
    typealias Identity = String
    
    var identity: String {
        return ""
    }
    
    init(original: FileContainer.Section, items: [FileContainer.Model]) {
        self = original
        self.items = items
    }
}

private class MosaicLayout: UICollectionViewLayout {
    var contentBounds = CGRect.zero
    var cachedAttributes = [UICollectionViewLayoutAttributes]()
    var cellHeight: CGFloat = 130
    
    /// - Tag: PrepareMosaicLayout
    override func prepare() {
        guard let collectionView = collectionView, collectionView.numberOfSections > 0 else { return }
        
        super.prepare()
        // Reset cached information.
        cachedAttributes.removeAll()
        contentBounds = CGRect(origin: .zero, size: collectionView.bounds.size)
        
        let count = collectionView.numberOfItems(inSection: 0)
        var currentIndex = 0
        var segment: MosaicSegmentStyle = .fullWidth
        var lastFrame: CGRect = .zero
        
        let cvWidth = collectionView.bounds.size.width
        
        let segmentFrame = CGRect(x: 0, y: lastFrame.maxY + 1.0, width: cvWidth, height: cellHeight)
        guard count > 0 else { return }
        
        switch count {
        case 2:
            segment = .fiftyFifty
        case 3:
            segment = .twoThirdsOneThird
        case 4:
            segment = .fourth
        default:
            segment = .fullWidth
        }
        
        var segmentRects = [CGRect]()
        switch segment {
        case .fullWidth:
            segmentRects = [segmentFrame]
            
        case .fiftyFifty:
            let horizontalSlices = segmentFrame.dividedIntegral(fraction: 0.5, from: .minXEdge)
            segmentRects = [horizontalSlices.first, horizontalSlices.second]
            
        case .twoThirdsOneThird:
            let horizontalSlices = segmentFrame.dividedIntegral(fraction: 2.0 / 3.0, from: .minXEdge)
            let verticalSlices = horizontalSlices.second.dividedIntegral(fraction: 0.5, from: .minYEdge)
            segmentRects = [horizontalSlices.first, verticalSlices.first, verticalSlices.second]
            
        case .oneThirdTwoThirds:
            let horizontalSlices = segmentFrame.dividedIntegral(fraction: 1.0 / 3.0, from: .minXEdge)
            let verticalSlices = horizontalSlices.first.dividedIntegral(fraction: 0.5, from: .minYEdge)
            segmentRects = [verticalSlices.first, verticalSlices.second, horizontalSlices.second]
            
        case .fourth:
            let horizontalSlices = segmentFrame.dividedIntegral(fraction: 0.5, from: .minXEdge)
            let leftBlock = horizontalSlices.first.dividedIntegral(fraction: 0.5, from: .minYEdge)
            let rightBlock = horizontalSlices.second.dividedIntegral(fraction: 0.5, from: .minYEdge)
            segmentRects = [leftBlock.first, rightBlock.first, leftBlock.second, rightBlock.second]
        }
        
        // Create and cache layout attributes for calculated frames.
        for rect in segmentRects {
            let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: currentIndex, section: 0))
            attributes.frame = rect
            
            cachedAttributes.append(attributes)
            contentBounds = contentBounds.union(lastFrame)
            
            currentIndex += 1
            lastFrame = rect
        }
    }
    
    /// - Tag: CollectionViewContentSize
    override var collectionViewContentSize: CGSize {
        return contentBounds.size
    }
    
    /// - Tag: ShouldInvalidateLayout
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        guard let collectionView = collectionView else { return false }
        return !newBounds.size.equalTo(collectionView.bounds.size)
    }
    
    /// - Tag: LayoutAttributesForItem
    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard indexPath.item < cachedAttributes.count else { return nil }
        return cachedAttributes[indexPath.item]
    }
    
    /// - Tag: LayoutAttributesForElements
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        var attributesArray = [UICollectionViewLayoutAttributes]()
        
        // Find any cell that sits within the query rect.
        guard let lastIndex = cachedAttributes.indices.last,
            let firstMatchIndex = binSearch(rect, start: 0, end: lastIndex) else { return attributesArray }
        
        // Starting from the match, loop up and down through the array until all the attributes
        // have been added within the query rect.
        for attributes in cachedAttributes[..<firstMatchIndex].reversed() {
            guard attributes.frame.maxY >= rect.minY else { break }
            attributesArray.append(attributes)
        }
        
        for attributes in cachedAttributes[firstMatchIndex...] {
            guard attributes.frame.minY <= rect.maxY else { break }
            attributesArray.append(attributes)
        }
        
        return attributesArray
    }
    
    // Perform a binary search on the cached attributes array.
    func binSearch(_ rect: CGRect, start: Int, end: Int) -> Int? {
        if end < start { return nil }
        
        let mid = (start + end) / 2
        let attr = cachedAttributes[mid]
        
        if attr.frame.intersects(rect) {
            return mid
        } else {
            if attr.frame.maxY < rect.minY {
                return binSearch(rect, start: mid + 1, end: end)
            } else {
                return binSearch(rect, start: start, end: mid - 1)
            }
        }
    }
}

extension MosaicLayout {
    enum MosaicSegmentStyle {
        case fullWidth
        case fiftyFifty
        case twoThirdsOneThird
        case oneThirdTwoThirds
        case fourth
    }
}

extension CGRect {
    func dividedIntegral(fraction: CGFloat, from fromEdge: CGRectEdge) -> (first: CGRect, second: CGRect) {
        let dimension: CGFloat
        
        switch fromEdge {
        case .minXEdge, .maxXEdge:
            dimension = size.width
        case .minYEdge, .maxYEdge:
            dimension = size.height
        }
        
        let distance = (dimension * fraction).rounded(.up)
        var slices = divided(atDistance: distance, from: fromEdge)
        
        switch fromEdge {
        case .minXEdge, .maxXEdge:
            slices.remainder.origin.x += 1
            slices.remainder.size.width -= 1
        case .minYEdge, .maxYEdge:
            slices.remainder.origin.y += 1
            slices.remainder.size.height -= 1
        }
        
        return (first: slices.slice, second: slices.remainder)
    }
}
