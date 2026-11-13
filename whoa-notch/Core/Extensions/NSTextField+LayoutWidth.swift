import AppKit

extension NSTextField {

  /// Largeur à donner au champ pour qu'il pose son intitulé en entier.
  ///
  /// Ni `intrinsicContentSize.width` ni `NSString.size(withAttributes:)` ne conviennent : un
  /// `NSTextField` dessine son texte à l'intérieur d'une marge que ces deux mesures ne comptent
  /// pas, et un cadre posé à leur largeur rogne la dernière lettre — « Global » s'affichait
  /// « Globa », « Not connected » perdait son « d ». La cellule, elle, mesure ce qu'elle
  /// dessine.
  ///
  /// Arrondie au point supérieur : une largeur fractionnaire rogne elle aussi, d'un demi-pixel.
  var layoutWidth: CGFloat {
    ceil(cell?.cellSize.width ?? intrinsicContentSize.width)
  }
}
