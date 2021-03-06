#' ---
#' title: "Otto-Group Product-Classification Challenge"
#' author: "Leila JAMSHIDIAN SALES"
#' always_allow_html: yes
#' output: 
#'   pdf_document:
#'     number_sections: yes
#'     toc: yes
#' urlcolor: blue
#' ---
#' 
#' Problem Understanding
#' ============
#' 
#' Otto Group is a big company, selling many products. A dataset is provided for Multi-class classification task. Due to various processes used for information gathering, many identical products get classified differently. Therefore, the quality of product analysis depends heavily on the ability to accurately cluster similar products. The better the classification, the more insights we can be generated the product range. There are nine categories for all products. Each target category represents one of our most important product categories (like fashion, electronics, etc.). The products for the training and testing sets are selected randomly.
#' 
#' First we will prepare the **Otto** dataset and train a model, then we will generate vizualisations to get a clue of what is important to the model, finally, we will see how we can leverage these information.
#' 
#' Data Understanding and Preparation
#' =======================
#' 
#' This part is based on the **R** tutorial example by [Tong He](https://github.com/dmlc/xgboost/blob/master/demo/kaggle-otto/otto_train_pred.R) and [Micha�l Benesty](https://www.kaggle.com/tqchen/understanding-xgboost-model-on-otto-data/code).
#' 
#' First, let's load the packages and the dataset.
#' 
## ----loading-------------------------------------------------------------
require(methods)
require(data.table)
require(magrittr)
train <- fread('./otto_data/train.csv', header = T, stringsAsFactors = F)
test <- fread('./otto_data/test.csv', header=TRUE, stringsAsFactors = F)

#' > `magrittr` and `data.table` are here to make the code cleaner and much more rapid.
#' 
#' Let's explore the dataset.
#' 
## ----explore-------------------------------------------------------------
# Train dataset dimensions
dim(train)

# Training content
train[1:6,1:5, with =F]

# Test dataset dimensions
dim(train)

# Test content
test[1:6,1:5, with =F]

#' > We only display the 6 first rows and 5 first columns for convenience
#' 
#' Each *column* represents a feature measured by an integer. Each *row* is an **Otto** product.
#' 
#' Obviously the first column (`ID`) doesn't contain any useful information. 
#' 
#' To let the algorithm focus on real stuff, we will delete it.
#' 
## ----clean, results='hide'-----------------------------------------------
# Delete ID column in training dataset
train[, id := NULL]

# Delete ID column in testing dataset
test[, id := NULL]

#' 
#' Since it is a multi class classification challenge. We need to extract the labels (here the name of the different classes) from the training data. Usually the labels is in the first or the last column. We already know what is in the first column, let's check the content of the last one.
#' 
## ----searchLabel---------------------------------------------------------
# Check the content of the last column
train[1:6, ncol(train), with  = F]
# Save the name of the last column
nameLastCol <- names(train)[ncol(train)]

#' 
#' The classes are provided as character string in the **`r ncol(train)`**th column called **`r nameLastCol`** and they are in string format. So we will convert classes to integers for further processing. Moreover, we will start our indexing from 0 (e.g. class_1 maps to 0 and so on).
#' 
#' Hence, we will:
#' 
#' * extract the target column
#' * remove "Class_" from each class name
#' * convert to integers
#' * remove 1 to the new value
#' 
## ----classToIntegers-----------------------------------------------------
# Convert from classes to numbers
y <- train[, nameLastCol, with = F][[1]] %>% gsub('Class_','',.) %>% {as.integer(.) -1}
# Display the first 5 levels
y[1:5]

#' Doing One-Hot encoding of the label which we will use for feature analysis below.
#' 
## ----One-Hot encoding----------------------------------------------------
yMat <- model.matrix(~ target - 1, train)
colnames(yMat) <- 1:9

#' 
#' Finally, we remove **`r nameLastCol`** column from training dataset, otherwise our models will learn to just use **`r nameLastCol`** itself!
#' 
## ----deleteCols, results='hide'------------------------------------------
train[, (nameLastCol):=NULL, with = F]

#' 
#' Plotting the linear correlation between classes and features
## ----feature correlation, fig.width=10,fig.height=13---------------------

#Calculation linear correlation between classes and features
linearCor <- abs(cor(train, yMat))

library("ggplot2")
heatmapMatrix <- function(mat, xlab = "X", ylab = "Y", zlab = "Z", low = "white", high = "black",
                          grid = "grey", limits = NULL, legend.position = "top", colours = NULL){
  nr <- nrow(mat)
  nc <- ncol(mat)
  rnames <- rownames(mat)
  cnames <- colnames(mat)
  if(is.null(rnames)) rnames <- paste(xlab, 1:nr, sep = "_")
  if(is.null(cnames)) cnames <- paste(ylab, 1:nc, sep = "_")
  x <- rep(rnames, nc)
  y <- rep(cnames, each = nr)
  df <- data.frame(factor(x, levels = unique(x)),
                   factor(y, levels = unique(y)),
                   as.vector(mat))
  colnames(df) <- c(xlab, ylab, zlab)
  p <- ggplot(df, aes_string(ylab, xlab)) +
    geom_tile(aes_string(fill = zlab), colour = grid) +
      theme(legend.position=legend.position)
  if(is.null(colours)){
    p + scale_fill_gradient(low = low, high = high, limits = limits)
  }else{
    p + scale_fill_gradientn(colours = colours)
  }
}

p1 <- heatmapMatrix(linearCor, xlab = "X", ylab = "Class", zlab = "Corr", high = "blue")
plot(p1,height=5)

#' 
#' > As can be observed above, the feature-34 has high correlation with class-5, and class-6 also has high linear correlation with a bunch of features. Note that class-1 has low correlation with any feature, this means that class-1 is either non-linearly dependent on the features or there is no dependence at all.
#' 
#' Modelling
#' ==============
#' 
#' We shall now try and use various models train our classifier.
#' 
#' XGBoost
#' ---------
#' XGBoost is a popular implementation of Gradient Boosting methods. It builds a boosted boosted classifier/regressor with decision tree as its base-learner. The incremental weights added to each base-learner is based upon the gradient of some loss define over the space of classifer/regressor functions.
#' 
#' To begin with, note that `data.table` is not an implementation of data.frame which is natively supported by **XGBoost**. So, we need to convert both datasets (training and test) in numeric Matrix format.
#' 
## ----convertToNumericMatrix----------------------------------------------
trainMatrix <- train[,lapply(.SD,as.numeric)] %>% as.matrix
testMatrix <- test[,lapply(.SD,as.numeric)] %>% as.matrix

#' 
#' Before the learning we will use the cross validation to evaluate our error rate.
#' 
#' Basically **XGBoost** will divide the training data in `nfold` parts, then **XGBoost** will retain the first part and use it as the test data. Then it will reintegrate the first part to the training dataset and retain the second part, do a training and so on...
#' 
## ----crossValidation-----------------------------------------------------
library("xgboost")
numberOfClasses <- max(y) + 1

param <- list("objective" = "multi:softprob",
              "eval_metric" = "mlogloss",
              "num_class" = numberOfClasses)

cv.nround <- 5
cv.nfold <- 3

bst.cv = xgb.cv(param=param, data = trainMatrix, label = y, 
                nfold = cv.nfold, nrounds = cv.nround)

#' 
#' > As we can see the error rate is low on the test dataset (for a 5mn trained model).
#' 
#' Finally, we train a real model:
#' 
## ----modelTraining-------------------------------------------------------
nround = 50
bst = xgboost(param=param, data = trainMatrix, label = y, nrounds=nround)

#' 
#' Feature importance
#' ------------------
#' 
#' So far, we have built a model made of **`r nround`** trees.
#' 
#' To build a tree, the dataset is divided recursively several times. At the end of the process, you get groups of observations (here, these observations are properties regarding **Otto** products). 
#' 
#' Each division operation is called a *split*.
#' 
#' Each group at each division level is called a branch and the deepest level is called a **leaf**.
#' 
#' In the final model, these leafs are supposed to be as pure as possible for each tree, meaning in our case that each leaf should be made of one class of **Otto** product only (of course it is not true, but that's what we try to achieve in a minimum of splits).
#' 
#' **Not all splits are equally important**. Basically the first split of a tree will have more impact on the purity than, for instance, the deepest split. Intuitively, we understand that the first split makes most of the work, and the following splits focus on smaller parts of the dataset which have been missclassified by the first tree.
#' 
#' In the same way, in Boosting we try to optimize the missclassification at each round (it is called the **loss**). So the first tree will do the big work and the following trees will focus on the remaining, on the parts not correctly learned by the previous trees.
#' 
#' The improvement brought by each split can be measured, it is the **gain**.
#' 
#' Each split is done on one feature only at one value. 
#' 
#' Let's see what the model looks like.
#' 
## ----modelDump-----------------------------------------------------------
model <- xgb.dump(bst, with.stats = T)
model[1:10]

#' > For convenience, we are displaying the first 10 lines of the model only.
#' 
#' Clearly, it is not easy to understand what it means. 
#' 
#' Basically each line represents a branch, there is the tree ID, the feature ID, the point where it splits, and information regarding the next branches (left, right, when the row for this feature is N/A).
#' 
#' Fortunately, **XGBoost** offers better visual representation for the learnt model.
#' 
#' Feature importance is about averaging the gain of each feature for all split and all trees. Another important aspect would be to know the distribution of obersevations are various leaves (and at what depth do these leaf nodes occur).
#' we can use the functions `xgb.plot.importance` and `xgb.plot.deepness` for this purpose.
#' 
## ----importanceFeature, fig.align='center', fig.height=5, fig.width=10----
# Get the feature real names
names <- dimnames(trainMatrix)[[2]]

# Compute feature importance matrix
importance_matrix <- xgb.importance(names, model = bst)

# Graph of feature importance
xgb.plot.importance(importance_matrix[1:10,])

# Another important visualization
xgb.plot.deepness(model = bst)

#' 
#' 
#' Interpretation
#' --------------
#' 
#' In the feature importance above, we can see the first 10 most important features. This function gives a color to each bar. Basically a K-means clustering is applied to group each feature by importance.
#' 
#' For the depth visualizations, first plot plots a histogram of leaves at varying nodes. The y-axis on the second plot says **cover**, which means that it specifies the weighted observations at each depth. Note that the observations are weighted as the algorithm weghts each observation again, for learning the next base-learner that is to be added to the ensemble.
#' 
#' Therefore decision-trees in general serve the dual purpose of being a classifier and as a useful pre-processing tool. From here on, one can take several steps. For instance we can remove the less important feature (feature selection process), or go deeper into the interaction between the most important features and labels.
#' 
#' Or we could just reason about why these features are so important (in **Otto** challenge we can't go this way because there is not enough information).
#' 
## ----treeGraph, echo=FALSE-----------------------------------------------
#treegraph <- xgb.plot.tree(feature_names = names, model = bst, n_first_tree = 2)
#typeof(treegraph)
#DiagrammeR::generate_dot(treegraph)
#DiagrammeR::export_graph(treegraph, 'tree.png', width=3000, height=4000)

#' 
#' 
#' Evaluation and Deployment
#' ============
#' 
## ----submission----------------------------------------------------------
#Build submission
submit <- predict(bst, testMatrix, type="prob") 
# shrink the size of submission
submit <- format(submit, digits=2, scientific = FALSE)
submit <- cbind(id=1:nrow(testMatrix), submit) 
#Write to csv
write.csv(submit, "submit.csv", row.names=FALSE)

#' 
#' The test-score of our model is 0.54, which gives us a position of less than 2000 on the leaderboard.
#' 
#' Going deeper
#' ============
#' 
#' There are 3 documents you may be interested in:
#' 
#' * [xgboostPresentation.Rmd](https://github.com/dmlc/xgboost/blob/master/R-package/vignettes/xgboostPresentation.Rmd): general presentation
#' * [discoverYourData.Rmd](https://github.com/dmlc/xgboost/blob/master/R-package/vignettes/discoverYourData.Rmd): explaining feature analysus
#' * [Feature Importance Analysis with XGBoost in Tax audit](http://fr.slideshare.net/MichaelBENESTY/feature-importance-analysis-with-xgboost-in-tax-audit): use case
#' * [Fast caliberated KNN](https://github.com/davpinto/fastknn): use case of KNN features combined with Generalized Linear Models (GLM).
#' * [Example Kaggle kernel for FKNN](https://www.kaggle.com/davidpinto/fastknn-show-to-glm-what-knn-see-0-96): See kaggle kernel for more details.
#' 
