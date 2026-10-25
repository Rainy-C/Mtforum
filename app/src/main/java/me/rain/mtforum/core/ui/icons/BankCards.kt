// Copyright 2025, compose-miuix-ui contributors
// SPDX-License-Identifier: Apache-2.0

package me.rain.mtforum.core.ui.icons

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathNode
import androidx.compose.ui.graphics.vector.group
import androidx.compose.ui.unit.dp

val MiuixNavigationIcons.BankCards: ImageVector
    get() {
        if (_bankcardsRegular != null) return _bankcardsRegular!!
        _bankcardsRegular =
            ImageVector.Builder(
                    name = "BankCards.Regular",
                    defaultWidth = 24.0f.dp,
                    defaultHeight = 24.0f.dp,
                    viewportWidth = 1224.0f,
                    viewportHeight = 1224.0f,
                )
                .apply {
                    group(scaleY = -1.0f, translationY = 1224.0f) {
                        addPath(
                            pathData =
                                listOf(
                                    PathNode.MoveTo(1044.0f, 232.0f),
                                    PathNode.QuadTo(1085.0f, 254.0f, 1107.0f, 295.0f),
                                    PathNode.QuadTo(1117.0f, 316.0f, 1119.5f, 345.5f),
                                    PathNode.QuadTo(1122.0f, 375.0f, 1122.0f, 445.0f),
                                    PathNode.VerticalTo(741.0f),
                                    PathNode.HorizontalTo(102.0f),
                                    PathNode.VerticalTo(445.0f),
                                    PathNode.QuadTo(102.0f, 375.0f, 104.5f, 345.5f),
                                    PathNode.QuadTo(107.0f, 316.0f, 117.0f, 295.0f),
                                    PathNode.QuadTo(139.0f, 254.0f, 180.0f, 232.0f),
                                    PathNode.QuadTo(201.0f, 222.0f, 230.5f, 219.5f),
                                    PathNode.QuadTo(260.0f, 217.0f, 330.0f, 217.0f),
                                    PathNode.HorizontalTo(894.0f),
                                    PathNode.QuadTo(964.0f, 217.0f, 993.5f, 219.5f),
                                    PathNode.QuadTo(1023.0f, 222.0f, 1044.0f, 232.0f),
                                    PathNode.Close,
                                    PathNode.MoveTo(734.0f, 395.0f),
                                    PathNode.VerticalTo(438.0f),
                                    PathNode.QuadTo(734.0f, 470.0f, 747.5f, 483.0f),
                                    PathNode.QuadTo(761.0f, 496.0f, 792.0f, 496.0f),
                                    PathNode.HorizontalTo(898.0f),
                                    PathNode.QuadTo(929.0f, 496.0f, 942.5f, 483.0f),
                                    PathNode.QuadTo(956.0f, 470.0f, 956.0f, 438.0f),
                                    PathNode.VerticalTo(395.0f),
                                    PathNode.QuadTo(956.0f, 363.0f, 942.5f, 349.5f),
                                    PathNode.QuadTo(929.0f, 336.0f, 898.0f, 336.0f),
                                    PathNode.HorizontalTo(792.0f),
                                    PathNode.QuadTo(761.0f, 336.0f, 747.5f, 349.5f),
                                    PathNode.QuadTo(734.0f, 363.0f, 734.0f, 395.0f),
                                    PathNode.Close,
                                    PathNode.MoveTo(1107.0f, 930.0f),
                                    PathNode.QuadTo(1085.0f, 971.0f, 1044.0f, 992.0f),
                                    PathNode.QuadTo(1023.0f, 1002.0f, 993.5f, 1004.5f),
                                    PathNode.QuadTo(964.0f, 1007.0f, 894.0f, 1007.0f),
                                    PathNode.HorizontalTo(330.0f),
                                    PathNode.QuadTo(260.0f, 1007.0f, 230.5f, 1004.5f),
                                    PathNode.QuadTo(201.0f, 1002.0f, 180.0f, 992.0f),
                                    PathNode.QuadTo(139.0f, 971.0f, 117.0f, 930.0f),
                                    PathNode.QuadTo(108.0f, 911.0f, 105.0f, 884.0f),
                                    PathNode.QuadTo(102.0f, 857.0f, 102.0f, 807.0f),
                                    PathNode.HorizontalTo(1122.0f),
                                    PathNode.QuadTo(1122.0f, 857.0f, 1119.0f, 884.0f),
                                    PathNode.QuadTo(1116.0f, 911.0f, 1107.0f, 930.0f),
                                    PathNode.Close,
                                ),
                            fill = SolidColor(Color.Black),
                            fillAlpha = 1f,
                            pathFillType = PathFillType.NonZero,
                        )
                    }
                }
                .build()
        return _bankcardsRegular!!
    }

private var _bankcardsRegular: ImageVector? = null
